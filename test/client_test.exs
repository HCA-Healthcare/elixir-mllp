defmodule ClientTest do
  use ExUnit.Case, async: false
  alias MLLP.Client
  alias MLLP.Client.Error

  import Mox
  import ExUnit.CaptureLog
  @moduletag capture_log: true

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    attach_telemetry()
    on_exit(fn -> detach_telemetry() end)
  end

  describe "host parameters" do
    test "accepts ipv4 / ipv6 tuples and binaries for host parameter" do
      assert {:ok, _} = MLLP.Client.start_link({127, 0, 0, 1}, 9999)

      assert {:ok, _} = MLLP.Client.start_link({0, 0, 0, 0, 0, 0, 0, 1}, 9999)

      assert {:ok, _} = MLLP.Client.start_link("127.0.0.1", 9999)

      assert {:ok, _} = MLLP.Client.start_link("::1", 9999)

      assert {:ok, _} = MLLP.Client.start_link(:localhost, 9999)
      assert {:ok, _} = MLLP.Client.start_link("servera.app.net", 9999)
      assert {:ok, _} = MLLP.Client.start_link('servera.unix.city.net', 9999)
      assert {:ok, _} = MLLP.Client.start_link('127.0.0.1', 9999)
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
          'TLS client: In state wait_cert_cr at ssl_handshake.erl:2017 generated CLIENT ALERT: Fatal - Handshake Failure\n {bad_cert,hostname_check_failed}'}}

      exp =
        "TLS client: In state wait_cert_cr at ssl_handshake.erl:2017 generated CLIENT ALERT: Fatal - Handshake Failure\n {bad_cert,hostname_check_failed}"

      assert MLLP.Client.format_error(err) == exp
    end

    test "when given a string" do
      assert MLLP.Client.format_error("some unknown error") == "some unknown error"
    end

    test "when given terms that are not atoms" do
      assert MLLP.Client.format_error(:eh?) == ":eh?"
      assert MLLP.Client.format_error({:error, 42}) == "{:error, 42}"
    end
  end

  describe "socket_opts" do
    test "with default options" do
      address = {127, 0, 0, 1}
      port = 4090
      socket = make_ref()

      expect(MLLP.TCPMock, :connect, fn ^address, ^port, opts, 2000 ->
        # Assert we received the default options
        assert opts[:send_timeout] == 60_000
        {:ok, socket}
      end)

      {:ok, pid} = Client.start_link(address, port, tcp: MLLP.TCPMock)
      {_fsm_state, state} = :sys.get_state(pid)

      # Assert we have the correct socket_opts in the state
      assert state.socket_opts == [send_timeout: 60_000]
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
      assert state.socket_opts == [send_timeout: 10_000]
    end

    test "with additional options" do
      address = {127, 0, 0, 1}
      port = 4090
      socket = make_ref()
      socket_opts = [keepalive: true]

      expect(MLLP.TCPMock, :connect, fn ^address, ^port, opts, 2000 ->
        # Assert we received the default options
        assert opts[:send_timeout] == 60_000
        assert opts[:keepalive] == true
        {:ok, socket}
      end)

      {:ok, pid} = Client.start_link(address, port, tcp: MLLP.TCPMock, socket_opts: socket_opts)
      {_fsm_state, state} = :sys.get_state(pid)

      # Assert we have the correct socket_opts in the state
      assert state.socket_opts[:send_timeout] == 60_000
      assert state.socket_opts[:keepalive] == true
    end
  end

  describe "uses backoff to handle connection" do
    test "with base state" do
      address = {127, 0, 0, 1}
      port = 4090
      socket = make_ref()

      expect(MLLP.TCPMock, :connect, fn ^address,
                                        ^port,
                                        [
                                          :binary,
                                          {:packet, 0},
                                          {:active, true},
                                          {:send_timeout, 60_000}
                                        ],
                                        2000 ->
        {:ok, socket}
      end)

      {:ok, pid} = Client.start_link(address, port, tcp: MLLP.TCPMock, use_backoff: true)

      {_fsm_state, state} = :sys.get_state(pid)

      assert {:backoff, 1, 180, 1, :normal, _, _} = state.backoff
    end

    test "after connection failure" do
      address = {127, 0, 0, 1}
      port = 4090

      expect(MLLP.TCPMock, :connect, fn ^address,
                                        ^port,
                                        [
                                          :binary,
                                          {:packet, 0},
                                          {:active, true},
                                          {:send_timeout, 60_000}
                                        ],
                                        2000 ->
        {:error, "error"}
      end)

      {:ok, pid} = Client.start_link(address, port, tcp: MLLP.TCPMock, use_backoff: true)

      {_fsm_state, state} = :sys.get_state(pid)

      assert {:backoff, 1, 180, 2, :normal, _, _} = state.backoff
    end
  end

  describe "handle_info/2" do
    test "handles unexpected info messages" do
      assert {:ok, pid} = MLLP.Client.start_link({127, 0, 0, 1}, 9998, use_backoff: true)

      assert capture_log(fn ->
               Kernel.send(pid, :eh?)
               Process.sleep(100)
               assert Process.alive?(pid)
             end) =~ "Unknown message received => :eh?"
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
          {:ok, :application_accept, expected_ack} ==
            Client.send(ctx.client, message)
        end)

      fragment_log = "Client #{inspect(ctx.client)} received a MLLP fragment"
      ## One fragment...
      assert count_occurences(log, fragment_log) == 1
      ## ..before the MLLP is fully received
      received_log = "Client #{inspect(ctx.client)} received a full MLLP!"
      num_receives = count_occurences(log, received_log)

      assert num_receives == 1
    end

    test "when replies are fragmented and the last fragment is not received", ctx do
      ## for this HL7 message, TestDispatcher implementation cuts the trailer (note NOTRAILER)
      ## , which should result in the client timing out while waiting for the last fragment.
      message =
        "MSH|^~\\&|SuperOE|XYZImgCtr|MegaReg|XYZHospC|20060529090131-0500||ACK^O01|NOTRAILER|P|2.5\rMSA|AA|NOTRAILER\r"

      expected_err = %MLLP.Client.Error{context: :recv, reason: :timeout, message: "timed out"}

      log =
        capture_log([level: :debug], fn ->
          {:error, expected_err} ==
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

    test "when reply header is invalid", ctx do
      ## This HL7 message triggers :invalid_reply due to TestDispatcher implementation (note DONOTWRAP!)
      message =
        "MSH|^~\\&|SuperOE|XYZImgCtr|MegaReg|XYZHospC|20060529090131-0500||ACK^O01|DONOTWRAP|P|2.5\rMSA|AA|DONOTWRAP\r"

      expected_err = %MLLP.Client.Error{
        context: :recv,
        message: "Invalid header received in server acknowledgment",
        reason: :invalid_reply
      }

      assert(
        {:error, expected_err} ==
          Client.send(ctx.client, message)
      )
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

      MLLP.TCPMock
      |> expect(
        :connect,
        fn ^address,
           ^port,
           [:binary, {:packet, 0}, {:active, true}, {:send_timeout, 60_000}],
           2000 ->
          {:ok, socket}
        end
      )
      |> expect(:send, fn ^socket, ^packet -> {:error, :closed} end)

      {:ok, client} = Client.start_link(address, port, tcp: MLLP.TCPMock)

      assert {:error, %Error{message: "connection closed", context: :send, reason: :closed}} ==
               Client.send(client, message)
    end

    test "one send request at a time", ctx do
      test_message = "test_one_send_at_a_time"

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

      MLLP.TCPMock
      |> expect(
        :connect,
        fn ^address,
           ^port,
           [:binary, {:packet, 0}, {:active, true}, {:send_timeout, 60_000}],
           2000 ->
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

      MLLP.TCPMock
      |> expect(
        :connect,
        fn ^address,
           ^port,
           [:binary, {:packet, 0}, {:active, true}, {:send_timeout, 60_000}],
           2000 ->
          {:ok, socket}
        end
      )
      |> expect(:send, fn ^socket, ^packet -> {:error, :closed} end)

      {:ok, client} = Client.start_link(address, port, tcp: MLLP.TCPMock)

      assert {:error, %Error{message: "connection closed", context: :send, reason: :closed}} ==
               Client.send_async(client, message)
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

  defp setup_client_receiver() do
    address = {127, 0, 0, 1}
    port = 4090
    {:ok, _receiver} = MLLP.Receiver.start(port: port, dispatcher: ClientTest.TestDispatcher)
    {:ok, client} = Client.start_link(address, port, tcp: MLLP.TCP)

    on_exit(fn ->
      MLLP.Receiver.stop(port)
      Process.sleep(100)
      Process.exit(client, :kill)
    end)

    %{client: client}
  end

  defp telemetry_event(
         [:mllp, :client, event_name] = _full_event_name,
         measurements,
         metadata,
         config
       ) do
    send(
      config.test_pid,
      {:telemetry_call, %{event_name: event_name, measurements: measurements, metadata: metadata}}
    )
  end

  defp attach_telemetry() do
    event_names =
      [:status, :sending, :received]
      |> Enum.map(fn e -> [:mllp, :client, e] end)

    :telemetry.attach_many("telemetry_events", event_names, &telemetry_event/4, %{
      test_pid: self()
    })
  end

  defp detach_telemetry() do
    :telemetry.detach("telemetry_events")
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
      {:ok, %{state | reply_buffer: MLLP.Envelope.wrap_message(message)}}
    end

    defp handle_message(message) do
      ## Slow down the handling on receiver side
      Process.sleep(10)

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
    end
  end
end
