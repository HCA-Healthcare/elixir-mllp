defmodule ClientTest do
  use ExUnit.Case, async: false
  alias MLLP.Client
  alias MLLP.Client.Error

  import Mox
  import ExUnit.CaptureLog
  @moduletag capture_log: true

  setup :verify_on_exit!
  setup :set_mox_global

  describe "host parameters" do
    test "accepts ipv4 / ipv6 tuples and binaries for host parameter" do
      assert match?({:ok, _}, MLLP.Client.start_link({127, 0, 0, 1}, 9999))

      assert match?({:ok, _}, MLLP.Client.start_link({0, 0, 0, 0, 0, 0, 0, 1}, 9999))

      assert match?({:ok, _}, MLLP.Client.start_link("127.0.0.1", 9999))

      assert match?({:ok, _}, MLLP.Client.start_link("::1", 9999))

      assert match?({:ok, _}, MLLP.Client.start_link(:localhost, 9999))
      assert match?({:ok, _}, MLLP.Client.start_link("servera.app.net", 9999))
      assert match?({:ok, _}, MLLP.Client.start_link(~c"servera.unix.city.net", 9999))
      assert match?({:ok, _}, MLLP.Client.start_link(~c"127.0.0.1", 9999))
    end

    test "raises on invalid addresses" do
      assert_raise ArgumentError, fn -> MLLP.Client.start_link({127, 0, 0}, 9999) end
    end
  end

  describe "format_error/2" do
    test "when given gen_tcp errors" do
      assert MLLP.Client.format_error(:closed) == "connection closed"
      assert MLLP.Client.format_error(:timeout) == "timed out"

      assert MLLP.Client.format_error(:system_limit) ==
               "all available erlang emulator ports in use"

      assert MLLP.Client.format_error(:invalid_reply) ==
               "Invalid header received in server acknowledgment"
    end

    test "when given posix error" do
      assert MLLP.Client.format_error(:econnrefused) == "connection refused"
      assert MLLP.Client.format_error(:ewouldblock) == "operation would block"
      assert MLLP.Client.format_error(:econnreset) == "connection reset by peer"
    end

    test "when given ssl error" do
      err =
        {:tls_alert,
         {:handshake_failure,
          ~c"TLS client: In state wait_cert_cr at ssl_handshake.erl:2017 generated CLIENT ALERT: Fatal - Handshake Failure\n {bad_cert,hostname_check_failed}"}}

      exp =
        "TLS client: In state wait_cert_cr at ssl_handshake.erl:2017 generated CLIENT ALERT: Fatal - Handshake Failure\n {bad_cert,hostname_check_failed}"

      assert MLLP.Client.format_error(err) == exp
    end

    test "when given a string" do
      assert MLLP.Client.format_error("some unknown error") == "some unknown error"
    end

    test "when given atoms (which are not POSIX errors)" do
      assert MLLP.Client.format_error(:eh?) == ":eh?"
    end

    test "when given terms" do
      assert MLLP.Client.format_error({:error, 42}) == "{:error, 42}"
    end
  end

  describe "socket_opts" do
    test "with default options" do
      address = {127, 0, 0, 1}
      port = 4090

      {:ok, pid} = Client.start_link(address, port, tcp: MLLP.TCP)
      {_fsm_state, state} = :sys.get_state(pid)

      # Assert we have the correct socket_opts in the state
      assert Keyword.equal?(state.socket_opts, Client.default_socket_opts())
    end

    test "with default options overridden" do
      address = {127, 0, 0, 1}
      port = 4090
      socket = make_ref()
      socket_opts = [send_timeout: 10_000]

      expect(MLLP.TCPMock, :connect, fn ^address, ^port, opts, 2000 ->
        # Assert we received the default options
        assert opts[:send_timeout] == 10_000
        {:ok, socket}
      end)

      {:ok, pid} = Client.start_link(address, port, tcp: MLLP.TCPMock, socket_opts: socket_opts)
      {_fsm_state, state} = :sys.get_state(pid)

      # Assert we have the correct socket_opts in the state
      assert state.socket_opts[:send_timeout] == 10_000
    end

    test "with additional options" do
      address = {127, 0, 0, 1}
      port = 4090
      socket = make_ref()
      socket_opts = [keepalive: true]

      expect(MLLP.TCPMock, :connect, fn ^address, ^port, opts, 2000 ->
        # Assert we received the default options
        assert opts[:send_timeout] == 60_000
        assert opts[:keepalive]
        {:ok, socket}
      end)

      {:ok, pid} = Client.start_link(address, port, tcp: MLLP.TCPMock, socket_opts: socket_opts)
      {_fsm_state, state} = :sys.get_state(pid)

      # Assert we have the correct socket_opts in the state
      assert state.socket_opts[:send_timeout] == 60_000
      assert state.socket_opts[:keepalive]
    end
  end

  describe "uses backoff to handle connection" do
    setup do
      Logger.configure(level: :debug)
      setup_client_receiver()
    end

    test "with base state", ctx do
      {_fsm_state, state} = :sys.get_state(ctx.client)

      assert match?({:backoff, 1, 180, 1, :normal, _, _}, state.backoff)
    end

    test "after connection failure", ctx do
      # Stop the receiver...
      MLLP.Receiver.stop(ctx.port)

      # ... and wait for backoff to change
      Process.sleep(1000 + 100)

      {_fsm_state, state} = :sys.get_state(ctx.client)

      assert match?({:backoff, 1, 180, 2, :normal, _, _}, state.backoff)
    end

    test "the backoff will be reset every time 'send' call fails",
         %{client: client, port: port} = _ctx do
      # Stop the receiver...
      MLLP.Receiver.stop(port)

      # ... and wait for backoff to change; the delay below would set next backoff timeout to 4.
      Process.sleep(3000 + 100)

      {_fsm_state, state} = :sys.get_state(client)

      {:backoff, 1, 180, backoff_timeout, :normal, _, _} = state.backoff
      assert backoff_timeout == 4

      {:error, _} = MLLP.Client.send(client, "no connection, this should fail")

      {_fsm_state, state} = :sys.get_state(client)
      {:backoff, 1, 180, backoff_timeout, :normal, _, _} = state.backoff

      assert backoff_timeout == 2
    end
  end

  describe "unexpected messages" do
    setup do
      Logger.configure(level: :debug)
      setup_client_receiver()
    end

    test "handles unexpected info messages", %{client: pid} = _ctx do
      assert capture_log(fn ->
               Kernel.send(pid, :eh?)
               Process.sleep(100)
               assert Process.alive?(pid)
             end) =~ "Unknown message received => :eh?"
    end

    test "handles unexpected incoming packet", %{client: pid} = _ctx do
      {_fsm_state, state} = :sys.get_state(pid)
      socket = state.socket

      log =
        capture_log([level: :debug], fn ->
          Kernel.send(pid, {:tcp, socket, "what's up?"})

          {:error, _} =
            Client.send(
              pid,
              "this should fail as the connection will be dropped on unexpected packet"
            )

          ## Give it some time to reconnect
          Process.sleep(10)
        end)

      assert String.contains?(log, Client.format_error(:unexpected_packet_received))
      assert String.contains?(log, "Connection closed")
      assert String.contains?(log, "Connection established")
      ## The connection had been closed, then re-established
      {start_closed, _} = :binary.match(log, "Connection closed")
      {start_established, _} = :binary.match(log, "Connection established")
      assert start_closed < start_established
    end
  end

  describe "send/2" do
    setup do
      Logger.configure(level: :debug)
      setup_client_receiver()
    end

    test "with valid HL7 returns an AA", ctx do
      raw_hl7 = HL7.Examples.wikipedia_sample_hl7()
      message = HL7.Message.new(raw_hl7)
      expected_ack = %MLLP.Ack{acknowledgement_code: "AA", text_message: ""}

      assert(
        {:ok, :application_accept, expected_ack} ==
          Client.send(ctx.client, message, %{reply_timeout: 1000})
      )
    end

    test "when replies are fragmented", ctx do
      raw_hl7 = HL7.Examples.nist_immunization_hl7()

      message = HL7.Message.new(raw_hl7)

      expected_ack = %MLLP.Ack{acknowledgement_code: "AA", text_message: ""}

      log =
        capture_log([level: :debug], fn ->
          assert {:ok, :application_accept, expected_ack} ==
                   Client.send(ctx.client, message)
        end)

      fragment_log = "Client #{inspect(ctx.client)} received a MLLP fragment"
      ## One fragment...
      assert count_occurences(log, fragment_log) == 1
      ## ..before the MLLP is fully received
      received_log = "Client #{inspect(ctx.client)} received a full MLLP!"
      num_receives = count_occurences(log, received_log)

      assert num_receives == 1

      assert_receive {:telemetry_event,
                      %{
                        event: [:mllp, :client, :receive_valid]
                      }},
                     100
    end

    test "when replies are fragmented and the last fragment is not received", ctx do
      ## for this HL7 message, TestDispatcher implementation cuts the trailer (note NOTRAILER)
      ## , which should result in the client timing out while waiting for the last fragment.
      message =
        "MSH|^~\\&|SuperOE|XYZImgCtr|MegaReg|XYZHospC|20060529090131-0500||ACK^O01|NOTRAILER|P|2.5\rMSA|AA|NOTRAILER\r"

      expected_err = %MLLP.Client.Error{
        context: :receiving,
        reason: :timeout,
        message: "timed out"
      }

      log =
        capture_log([level: :debug], fn ->
          assert {:error, expected_err} ==
                   Client.send(ctx.client, message, %{reply_timeout: 1000})
        end)

      fragment_log = "Client #{inspect(ctx.client)} received a MLLP fragment"
      ## One fragment...
      assert count_occurences(log, fragment_log) == 1
      ## ..but the MLLP has not been fully received
      received_log = "Client #{inspect(ctx.client)} received a full MLLP!"
      num_receives = count_occurences(log, received_log)

      assert num_receives == 0
    end

    test "when the trailer is split between fragments", ctx do
      {_, data} = :sys.get_state(ctx.client)
      frag1 = <<11, 121, 101, 115>> <> MLLP.Envelope.eb()
      ## CR is a single byte coming in the last fragment
      frag_cr = MLLP.Envelope.cr()

      log =
        capture_log([level: :debug], fn ->
          ## The buffer will be reset upon reception of full MLLP
          assert "" ==
                   MLLP.Client.receive_impl(frag1, data)
                   |> then(fn d ->
                     MLLP.Client.receive_impl(frag_cr, d)
                     |> Map.get(:receive_buffer)
                     |> IO.iodata_to_binary()
                   end)
        end)

      first_fragment_log = "Client #{inspect(self())} received a MLLP fragment"
      ## One fragment...
      assert count_occurences(log, first_fragment_log) == 1
      cr_fragment_log = "Client #{inspect(self())} received a full MLLP!"
      ## Trailer completed by second fragment
      assert count_occurences(log, cr_fragment_log) == 1
    end

    test "when reply header is invalid", ctx do
      ## This HL7 message triggers :invalid_reply due to TestDispatcher implementation (note DONOTWRAP!)
      message =
        "MSH|^~\\&|SuperOE|XYZImgCtr|MegaReg|XYZHospC|20060529090131-0500||ACK^O01|DONOTWRAP|P|2.5\rMSA|AA|DONOTWRAP\r"

      expected_err = %MLLP.Client.Error{
        context: :receiving,
        message: "Invalid header received in server acknowledgment",
        reason: :invalid_reply
      }

      assert(
        {:error, expected_err} ==
          Client.send(ctx.client, message)
      )

      assert_receive {:telemetry_event,
                      %{
                        event: [:mllp, :client, :invalid_response],
                        measurements: %{error: :no_header}
                      }},
                     100
    end

    test "when response contains data after the trailer", ctx do
      message = "This message has a TRAILER_WITHIN - beware!"

      expected_err = %MLLP.Client.Error{
        context: :receiving,
        message: "Data received after trailer",
        reason: :data_after_trailer
      }

      assert(
        {:error, expected_err} ==
          Client.send(ctx.client, message)
      )

      assert_receive {:telemetry_event,
                      %{
                        event: [:mllp, :client, :invalid_response],
                        measurements: %{error: :data_after_trailer}
                      }},
                     100
    end

    test "when given non hl7", ctx do
      message = "NON HL7"

      assert Client.is_connected?(ctx.client)

      assert {:ok, message} == Client.send(ctx.client, message)
    end

    test "when server closes connection on send" do
      address = {127, 0, 0, 1}
      port = 4090
      socket = make_ref()
      raw_hl7 = HL7.Examples.wikipedia_sample_hl7()
      message = HL7.Message.new(raw_hl7)
      packet = MLLP.Envelope.wrap_message(raw_hl7)
      socket_opts = Client.fixed_socket_opts() ++ Client.default_socket_opts()

      MLLP.TCPMock
      |> expect(
        :connect,
        fn ^address, ^port, ^socket_opts, 2000 ->
          {:ok, socket}
        end
      )
      |> expect(:send, fn ^socket, ^packet -> {:error, :closed} end)

      {:ok, client} = Client.start_link(address, port, tcp: MLLP.TCPMock)

      assert {:error, %Error{message: "connection closed", context: :sending, reason: :closed}} ==
               Client.send(client, message)
    end

    test "one send request at a time", ctx do
      test_message = "Test one send at a time (asking receiver to SLOWDOWN to prevent flakiness)"

      num_requests = 4

      concurrent_requests =
        Task.async_stream(1..num_requests, fn _i -> Client.send(ctx.client, test_message) end)
        |> Enum.map(fn {:ok, res} -> res end)

      assert length(concurrent_requests) == num_requests

      assert Enum.count(concurrent_requests, fn resp ->
               case resp do
                 {:ok, message} when message == test_message -> true
                 {:error, %MLLP.Client.Error{reason: :busy_with_other_call}} -> false
               end
             end) == 1
    end

    test "responses to concurrent requests don't get mixed", ctx do
      test_message = "test_concurrent_"

      num_requests = 10

      concurrent_requests =
        Task.async_stream(1..num_requests, fn request_id ->
          {request_id, Client.send(ctx.client, test_message <> "#{request_id}")}
        end)
        |> Enum.map(fn {:ok, res} -> res end)

      ## All successful responses match the requests
      assert Enum.all?(
               concurrent_requests,
               fn
                 {request_id, {:ok, incoming}} ->
                   incoming == test_message <> "#{request_id}"

                 {_request_id, {:error, %MLLP.Client.Error{reason: :busy_with_other_call}}} ->
                   true

                 _unexpected ->
                   false
               end
             )
    end

    test "handles requests while processing 'send'", %{client: client} = _ctx do
      slow_processing_msg = "Asking receiver to SLOWDOWN..."
      ## One process sends a message, other 2 ask if the client is connected
      send_task = Task.async(fn -> Client.send(client, slow_processing_msg) end)
      Process.sleep(10)
      ## The client is in receiving mode...
      {:receiving, _state} = :sys.get_state(client)
      ## ...and accepts other requests
      assert Enum.all?(1..2, fn _ -> Client.is_connected?(client) end)
      assert Task.await(send_task) == {:ok, slow_processing_msg}
    end
  end

  describe "send_async/2" do
    setup do
      setup_client_receiver()
    end

    test "as a message", ctx do
      raw_hl7 = HL7.Examples.wikipedia_sample_hl7()

      message =
        raw_hl7
        |> HL7.Message.new()

      assert({:ok, :sent} == Client.send_async(ctx.client, message))
    end

    test "when given non hl7" do
      address = {127, 0, 0, 1}
      port = 4090

      socket = make_ref()
      message = "Hello, it's me"
      packet = MLLP.Envelope.wrap_message(message)
      socket_opts = Client.fixed_socket_opts() ++ Client.default_socket_opts()

      MLLP.TCPMock
      |> expect(
        :connect,
        fn ^address, ^port, ^socket_opts, 2000 ->
          {:ok, socket}
        end
      )
      |> expect(:send, fn ^socket, ^packet -> :ok end)

      {:ok, client} = Client.start_link(address, port, tcp: MLLP.TCPMock)

      assert({:ok, :sent} == Client.send_async(client, message))
    end

    test "when server closes connection on send" do
      address = {127, 0, 0, 1}
      port = 4090
      socket = make_ref()
      raw_hl7 = HL7.Examples.wikipedia_sample_hl7()
      message = HL7.Message.new(raw_hl7)
      packet = MLLP.Envelope.wrap_message(raw_hl7)

      socket_opts = Client.fixed_socket_opts() ++ Client.default_socket_opts()

      MLLP.TCPMock
      |> expect(
        :connect,
        fn ^address, ^port, ^socket_opts, 2000 ->
          {:ok, socket}
        end
      )
      |> expect(:send, fn ^socket, ^packet -> {:error, :closed} end)

      {:ok, client} = Client.start_link(address, port, tcp: MLLP.TCPMock)

      assert {:error, %Error{message: "connection closed", context: :sending, reason: :closed}} ==
               Client.send_async(client, message)
    end
  end

  describe "telemetry" do
    setup do
      setup_client_receiver(use_backoff: false)
    end

    test "connect/send/reconnect events", ctx do
      ## Telemetry event is emitted upon successful connection...
      assert_receive {:telemetry_event, %{event: [:mllp, :client, :connection_success]}}, 100
      raw_hl7 = HL7.Examples.wikipedia_sample_hl7()
      message = HL7.Message.new(raw_hl7)
      ## ...and upon getting a successful response
      {:ok, _, _} = Client.send(ctx.client, message)
      assert_receive {:telemetry_event, %{event: [:mllp, :client, :receive_valid]}}, 100
      MLLP.Receiver.stop(ctx.port)
      ## ...and upon the connection being closed
      assert_receive {:telemetry_event,
                      %{
                        event: [:mllp, :client, :connection_closed],
                        measurements: %{error: :closed}
                      }},
                     100

      ## ...and upon reconnection attempt (within a second or so, we use default auto_reconnect)
      assert_receive {:telemetry_event,
                      %{
                        event: [:mllp, :client, :connection_failure],
                        measurements: %{error: :econnrefused}
                      }},
                     1200

      ## ...and upon successful reconnection
      start_receiver(ctx.port)
      assert_receive {:telemetry_event, %{event: [:mllp, :client, :connection_success]}}, 1200
    end
  end

  describe "terminate/2" do
    test "logs debug message when reason is :normal" do
      Logger.configure(level: :debug)
      {:ok, pid} = Client.start_link({127, 0, 0, 1}, 9999)
      {_fsm_state, state} = :sys.get_state(pid)

      assert capture_log([level: :debug], fn ->
               Client.terminate(:normal, state)
             end) =~ "Client socket terminated. Reason: :normal"
    end

    test "logs error for any other reason" do
      Logger.configure(level: :debug)
      {:ok, pid} = Client.start_link({127, 0, 0, 1}, 9999)
      {_fsm_state, state} = :sys.get_state(pid)

      assert capture_log([level: :error], fn ->
               Client.terminate(:shutdown, state)
             end) =~ "Client socket terminated. Reason: :shutdown"
    end
  end

  defp setup_client_receiver(opts \\ []) do
    Process.register(self(), :mock_telemetry_collector)
    address = {127, 0, 0, 1}
    port = Keyword.get(opts, :port, 4090)
    telemetry_module = Keyword.get(opts, :telemetry_module, ClientTest.TelemetryModule)
    use_backoff = Keyword.get(opts, :use_backoff, true)
    {:ok, receiver} = start_receiver(port)

    {:ok, client} =
      Client.start_link(address, port,
        tcp: MLLP.TCP,
        telemetry_module: telemetry_module,
        use_backoff: use_backoff
      )

    on_exit(fn ->
      try do
        MLLP.Receiver.stop(port)
      rescue
        _err -> :ok
      end

      Process.sleep(100)
      Process.exit(client, :kill)
    end)

    %{client: client, receiver: receiver, port: port}
  end

  defp start_receiver(port) do
    MLLP.Receiver.start(port: port, dispatcher: ClientTest.TestDispatcher)
  end

  defp count_occurences(str, substr) do
    str |> String.split(substr) |> length() |> Kernel.-(1)
  end

  defmodule TestDispatcher do
    require Logger

    @behaviour MLLP.Dispatcher

    def dispatch(:mllp_hl7, <<"MSH|NOREPLY", _rest::binary>>, state) do
      {:ok, %{state | reply_buffer: ""}}
    end

    def dispatch(:mllp_hl7, message, state) when is_binary(message) do
      reply =
        message
        |> MLLP.Ack.get_ack_for_message(:application_accept)
        |> to_string()
        |> Kernel.<>(message)
        |> handle_message()

      {:ok, %{state | reply_buffer: reply}}
    end

    def dispatch(_non_hl7_type, message, state) do
      {:ok, %{state | reply_buffer: handle_message(message)}}
    end

    defp handle_message(message) do
      ## Slow down the handling on receiver side, if required
      if String.contains?(message, "SLOWDOWN") do
        Process.sleep(100)
      end

      if String.contains?(message, "DONOTWRAP") do
        message
      else
        MLLP.Envelope.wrap_message(message)
        |> then(fn wrapped_message ->
          if String.contains?(wrapped_message, "NOTRAILER") do
            String.slice(wrapped_message, 0, String.length(message) - 1)
          else
            wrapped_message
          end
        end)
      end
      |> then(fn msg ->
        if String.contains?(msg, "TRAILER_WITHIN") do
          ## Insert trailer in the middle of the message
          {part1, part2} = String.split_at(msg, div(String.length(msg), 2))
          part1 <> MLLP.Envelope.eb_cr() <> part2
        else
          msg
        end
      end)
    end
  end

  defmodule TelemetryModule do
    def execute(event, measurements, metadata) do
      recipient = Process.whereis(:mock_telemetry_collector)

      send(
        recipient,
        {:telemetry_event, %{event: event, measurements: measurements, metadata: metadata}}
      )
    end
  end
end
