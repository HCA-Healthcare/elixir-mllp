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
                                          {:active, false},
                                          {:send_timeout, 60_000}
                                        ],
                                        2000 ->
        {:ok, socket}
      end)

      {:ok, pid} = Client.start_link(address, port, tcp: MLLP.TCPMock, use_backoff: true)

      state = :sys.get_state(pid)

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
                                          {:active, false},
                                          {:send_timeout, 60_000}
                                        ],
                                        2000 ->
        {:error, "error"}
      end)

      {:ok, pid} = Client.start_link(address, port, tcp: MLLP.TCPMock, use_backoff: true)

      state = :sys.get_state(pid)

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
             end) =~ "Unknown kernel message received => :eh?"
    end
  end

  describe "send/2" do
    test "with valid HL7 returns an AA" do
      address = {127, 0, 0, 1}
      port = 4090
      socket = make_ref()
      raw_hl7 = HL7.Examples.wikipedia_sample_hl7()
      message = HL7.Message.new(raw_hl7)
      packet = MLLP.Envelope.wrap_message(raw_hl7)

      tcp_reply =
        MLLP.Envelope.wrap_message(
          "MSH|^~\\&|SuperOE|XYZImgCtr|MegaReg|XYZHospC|20060529090131-0500||ACK^O01|01052901|P|2.5\rMSA|AA|01052901|You win!\r"
        )

      MLLP.TCPMock
      |> expect(
        :connect,
        fn ^address,
           ^port,
           [:binary, {:packet, 0}, {:active, false}, {:send_timeout, 60_000}],
           2000 ->
          {:ok, socket}
        end
      )
      |> expect(:send, fn ^socket, ^packet -> :ok end)
      |> expect(:recv, fn ^socket, 0, 60_000 -> {:ok, tcp_reply} end)

      {:ok, client} = Client.start_link(address, port, tcp: MLLP.TCPMock, use_backoff: true)

      expected_ack = %MLLP.Ack{acknowledgement_code: "AA", text_message: "You win!"}

      assert(
        {:ok, :application_accept, expected_ack} ==
          Client.send(client, message)
      )
    end

    test "when replies are fragmented" do
      address = {127, 0, 0, 1}
      port = 4090
      socket = make_ref()
      raw_hl7 = HL7.Examples.wikipedia_sample_hl7()
      message = HL7.Message.new(raw_hl7)
      packet = MLLP.Envelope.wrap_message(raw_hl7)

      tcp_reply1 =
        MLLP.Envelope.wrap_message(
          "MSH|^~\\&|SuperOE|XYZImgCtr|MegaReg|XYZHospC|20060529090131-0500||ACK^O01|01052901|P|2.5\rMSA|AA|01052901|You win!\r"
        )

      {ack_frag1, ack_frag2} = String.split_at(tcp_reply1, 50)

      MLLP.TCPMock
      |> expect(
        :connect,
        fn ^address,
           ^port,
           [:binary, {:packet, 0}, {:active, false}, {:send_timeout, 60_000}],
           2000 ->
          {:ok, socket}
        end
      )
      |> expect(:send, fn ^socket, ^packet -> :ok end)
      |> expect(:recv, fn ^socket, 0, 60_000 -> {:ok, ack_frag1} end)
      |> expect(:recv, fn ^socket, 0, 60_000 -> {:ok, ack_frag2} end)

      {:ok, client} = Client.start_link(address, port, tcp: MLLP.TCPMock, use_backoff: true)

      expected_ack = %MLLP.Ack{acknowledgement_code: "AA", text_message: "You win!"}

      assert(
        {:ok, :application_accept, expected_ack} ==
          Client.send(client, message)
      )

      {ack_frag1, ack_frag2} = String.split_at(tcp_reply1, 50)

      {ack_frag2, ack_frag3} = String.split_at(ack_frag2, 10)

      MLLP.TCPMock
      |> expect(:send, fn ^socket, ^packet -> :ok end)
      |> expect(:recv, fn ^socket, 0, 60_000 -> {:ok, ack_frag1} end)
      |> expect(:recv, fn ^socket, 0, 60_000 -> {:ok, ack_frag2} end)
      |> expect(:recv, fn ^socket, 0, 60_000 -> {:ok, ack_frag3} end)

      assert(
        {:ok, :application_accept, expected_ack} ==
          Client.send(client, message)
      )
    end

    test "when replies are fragmented and the last fragment is not received" do
      address = {127, 0, 0, 1}
      port = 4090
      socket = make_ref()
      raw_hl7 = HL7.Examples.wikipedia_sample_hl7()
      message = HL7.Message.new(raw_hl7)
      packet = MLLP.Envelope.wrap_message(raw_hl7)

      tcp_reply1 =
        MLLP.Envelope.wrap_message(
          "MSH|^~\\&|SuperOE|XYZImgCtr|MegaReg|XYZHospC|20060529090131-0500||ACK^O01|01052901|P|2.5\rMSA|AA|01052901|You win!\r"
        )

      {ack_frag1, ack_frag2} = String.split_at(tcp_reply1, 50)

      {ack_frag2, _ack_frag3} = String.split_at(ack_frag2, 10)

      MLLP.TCPMock
      |> expect(
        :connect,
        fn ^address,
           ^port,
           [:binary, {:packet, 0}, {:active, false}, {:send_timeout, 60_000}],
           2000 ->
          {:ok, socket}
        end
      )
      |> expect(:send, fn ^socket, ^packet -> :ok end)
      |> expect(:recv, fn ^socket, 0, _ ->
        Process.sleep(1)
        {:ok, ack_frag1}
      end)
      |> expect(:recv, fn ^socket, 0, _ ->
        Process.sleep(1)
        {:ok, ack_frag2}
      end)

      {:ok, client} =
        Client.start_link(address, port, tcp: MLLP.TCPMock, use_backoff: true, reply_timeout: 3)

      expected_err = %MLLP.Client.Error{context: :recv, reason: :timeout, message: "timed out"}

      assert(
        {:error, expected_err} ==
          Client.send(client, message)
      )
    end

    test "when reply header is invalid" do
      address = {127, 0, 0, 1}
      port = 4090
      socket = make_ref()
      raw_hl7 = HL7.Examples.wikipedia_sample_hl7()
      message = HL7.Message.new(raw_hl7)
      packet = MLLP.Envelope.wrap_message(raw_hl7)

      tcp_reply1 =
        "MSH|^~\\&|SuperOE|XYZImgCtr|MegaReg|XYZHospC|20060529090131-0500||ACK^O01|01052901|P|2.5\rMSA|AA|01052901|You win!\r"

      MLLP.TCPMock
      |> expect(
        :connect,
        fn ^address,
           ^port,
           [
             :binary,
             {:packet, 0},
             {:active, false},
             {:send_timeout, 60_000}
           ],
           2000 ->
          {:ok, socket}
        end
      )
      |> expect(:send, fn ^socket, ^packet -> :ok end)
      |> expect(:recv, fn ^socket, 0, 60_000 -> {:ok, tcp_reply1} end)

      {:ok, client} = Client.start_link(address, port, tcp: MLLP.TCPMock, use_backoff: true)

      expected_err = %MLLP.Client.Error{
        context: :recv,
        message: "Invalid header received in server acknowledgment",
        reason: :invalid_reply
      }

      assert(
        {:error, expected_err} ==
          Client.send(client, message)
      )
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
           [:binary, {:packet, 0}, {:active, false}, {:send_timeout, 60_000}],
           2000 ->
          {:ok, socket}
        end
      )
      |> expect(:send, fn ^socket, ^packet -> :ok end)
      |> expect(:recv, fn ^socket, 0, 60_000 -> {:ok, MLLP.Envelope.wrap_message("NACK")} end)

      {:ok, client} = Client.start_link(address, port, tcp: MLLP.TCPMock)

      assert {:ok, "NACK"} = Client.send(client, message)
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
           [:binary, {:packet, 0}, {:active, false}, {:send_timeout, 60_000}],
           2000 ->
          {:ok, socket}
        end
      )
      |> expect(:send, fn ^socket, ^packet -> {:error, :closed} end)

      {:ok, client} = Client.start_link(address, port, tcp: MLLP.TCPMock)

      assert {:error, %Error{message: "connection closed", context: :send}} =
               Client.send(client, message)
    end
  end

  describe "send_async/2" do
    test "as a message" do
      address = {127, 0, 0, 1}
      port = 4090
      socket = make_ref()

      raw_hl7 = HL7.Examples.wikipedia_sample_hl7()

      message =
        raw_hl7
        |> HL7.Message.new()

      packet = MLLP.Envelope.wrap_message(raw_hl7)

      MLLP.TCPMock
      |> expect(
        :connect,
        fn ^address,
           ^port,
           [:binary, {:packet, 0}, {:active, false}, {:send_timeout, 60_000}],
           2000 ->
          {:ok, socket}
        end
      )
      |> expect(:send, fn ^socket, ^packet -> :ok end)

      {:ok, client} = Client.start_link(address, port, tcp: MLLP.TCPMock)

      assert({:ok, :sent} == Client.send_async(client, message))
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
           [:binary, {:packet, 0}, {:active, false}, {:send_timeout, 60_000}],
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
           [:binary, {:packet, 0}, {:active, false}, {:send_timeout, 60_000}],
           2000 ->
          {:ok, socket}
        end
      )
      |> expect(:send, fn ^socket, ^packet -> {:error, :closed} end)

      {:ok, client} = Client.start_link(address, port, tcp: MLLP.TCPMock)

      assert {:error, %Error{message: "connection closed", context: :send}} =
               Client.send_async(client, message)
    end
  end

  describe "terminate/2" do
    test "logs debug message when reason is :normal" do
      Logger.configure(level: :debug)
      {:ok, pid} = Client.start_link({127, 0, 0, 1}, 9999)
      state = :sys.get_state(pid)

      assert capture_log([level: :debug], fn ->
               Client.terminate(:normal, state)
             end) =~ "Client socket terminated. Reason: :normal"
    end

    test "logs error for any other reason" do
      Logger.configure(level: :debug)
      {:ok, pid} = Client.start_link({127, 0, 0, 1}, 9999)
      state = :sys.get_state(pid)

      assert capture_log([level: :error], fn ->
               Client.terminate(:shutdown, state)
             end) =~ "Client socket terminated. Reason: :shutdown"
    end
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
end
