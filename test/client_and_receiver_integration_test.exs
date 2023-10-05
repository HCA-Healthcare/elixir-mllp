defmodule ClientAndReceiverIntegrationTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import Mox
  setup :verify_on_exit!
  setup :set_mox_global

  alias MLLP.Client.Error
  @moduletag capture_log: true

  setup ctx do
    ack = {
      :ok,
      :application_accept,
      %MLLP.Ack{
        acknowledgement_code: "AA",
        hl7_ack_message: nil,
        text_message: "A real MLLP message dispatcher was not provided"
      }
    }

    transport_opts = ctx[:transport_opts] || %{}
    allowed_clients = ctx[:allowed_clients] || []
    port = ctx[:port] || 9000

    [ack: ack, port: port, transport_opts: transport_opts, allowed_clients: allowed_clients]
  end

  describe "Supervision" do
    test "successfully starts up under a supervisor using a child spec" do
      port = 8999
      transport_opts = %{num_acceptors: 1, max_connections: 1, socket_opts: [delay_send: true]}

      opts = [
        ref: ReceiverSupervisionTest,
        port: port,
        transport_opts: transport_opts,
        dispatcher: MLLP.EchoDispatcher
      ]

      start_supervised!({MLLP.Receiver, opts})

      {:ok, client_pid} = MLLP.Client.start_link({127, 0, 0, 1}, port)

      capture_log(fn ->
        {:ok, _, _ack} =
          MLLP.Client.send(
            client_pid,
            HL7.Message.new(HL7.Examples.wikipedia_sample_hl7())
          )
      end)
    end

    test "child_spec/1 accepts and returns documented options" do
      port = 8999
      transport_opts = %{num_acceptors: 1, max_connections: 1, socket_opts: [delay_send: true]}

      opts = [
        ref: ReceiverSupervisionTest,
        port: port,
        transport_opts: transport_opts,
        dispatcher: MLLP.EchoDispatcher
      ]

      expected_spec = %{
        id: {:ranch_listener_sup, ReceiverSupervisionTest},
        start:
          {:ranch_listener_sup, :start_link,
           [
             ReceiverSupervisionTest,
             :ranch_tcp,
             %{
               max_connections: 1,
               num_acceptors: 1,
               socket_opts: [port: 8999, delay_send: true]
             },
             MLLP.Receiver,
             %{
               packet_framer_module: MLLP.DefaultPacketFramer,
               dispatcher_module: MLLP.EchoDispatcher,
               allowed_clients: %{},
               verify: nil,
               context: %{}
             }
           ]},
        type: :supervisor,
        modules: [:ranch_listener_sup],
        restart: :permanent,
        shutdown: :infinity
      }

      assert MLLP.Receiver.child_spec(opts) == expected_spec
    end
  end

  describe "Starting and stopping" do
    test "with a listener listening" do
      port = 8143

      {:ok, %{pid: receiver_pid}} =
        MLLP.Receiver.start(port: port, dispatcher: MLLP.EchoDispatcher)

      assert Process.alive?(receiver_pid)

      {:ok, client_pid} = MLLP.Client.start_link({127, 0, 0, 1}, port)
      assert Process.alive?(client_pid)

      assert MLLP.Client.is_connected?(client_pid)

      capture_log(fn -> MLLP.Client.stop(client_pid) end)
      refute Process.alive?(client_pid)

      MLLP.Receiver.stop(port)
      refute Process.alive?(receiver_pid)
    end

    test "without a listener" do
      port = 8144

      {:ok, client_pid} = MLLP.Client.start_link({127, 0, 0, 1}, port)
      assert Process.alive?(client_pid)

      refute MLLP.Client.is_connected?(client_pid)

      capture_log(fn -> MLLP.Client.stop(client_pid) end)
      refute Process.alive?(client_pid)

      {:ok, client_pid} = MLLP.Client.start_link({127, 0, 0, 1}, port)

      exp_err = %Error{context: :sending, reason: :econnrefused, message: "connection refused"}
      assert {:error, ^exp_err} = MLLP.Client.send(client_pid, "Eh?")
    end

    test "with a listener added late" do
      port = 8145

      {:ok, client_pid} = MLLP.Client.start_link({127, 0, 0, 1}, port)
      assert Process.alive?(client_pid)

      refute MLLP.Client.is_connected?(client_pid)

      {:ok, %{pid: receiver_pid}} =
        MLLP.Receiver.start(port: port, dispatcher: MLLP.EchoDispatcher)

      assert Process.alive?(receiver_pid)

      refute MLLP.Client.is_connected?(client_pid)

      MLLP.Client.reconnect(client_pid)
      assert MLLP.Client.is_connected?(client_pid)

      capture_log(fn -> MLLP.Client.stop(client_pid) end)
      refute Process.alive?(client_pid)

      MLLP.Receiver.stop(port)
      refute Process.alive?(receiver_pid)
    end

    test "with reconnecting" do
      port = 8146

      {:ok, client_pid} = MLLP.Client.start_link({127, 0, 0, 1}, port)
      assert Process.alive?(client_pid)

      refute MLLP.Client.is_connected?(client_pid)

      {:ok, %{pid: receiver_pid}} =
        MLLP.Receiver.start(port: port, dispatcher: MLLP.EchoDispatcher)

      assert Process.alive?(receiver_pid)

      refute MLLP.Client.is_connected?(client_pid)

      MLLP.Client.reconnect(client_pid)
      assert MLLP.Client.is_connected?(client_pid)
    end

    test "detection of disconnected receiver" do
      port = 8147

      {:ok, %{pid: _receiver_pid}} =
        MLLP.Receiver.start(port: port, dispatcher: MLLP.EchoDispatcher)

      {:ok, client_pid} = MLLP.Client.start_link({127, 0, 0, 1}, port)

      assert MLLP.Client.is_connected?(client_pid)

      MLLP.Receiver.stop(port)
      :timer.sleep(10)

      refute MLLP.Client.is_connected?(client_pid)
    end
  end

  describe "Sending and receiving" do
    test "without a listener listening" do
      port = 8150

      {:ok, client_pid} = MLLP.Client.start_link({127, 0, 0, 1}, port)
      assert Process.alive?(client_pid)

      payload = "A simple message"

      exp_err = %Error{context: :sending, reason: :econnrefused, message: "connection refused"}
      assert {:error, ^exp_err} = MLLP.Client.send(client_pid, payload)

      capture_log(fn -> MLLP.Client.stop(client_pid) end)
      refute Process.alive?(client_pid)
    end

    test "with a receiver that stops before the send" do
      port = 8151

      {:ok, %{pid: receiver_pid}} =
        MLLP.Receiver.start(port: port, dispatcher: MLLP.EchoDispatcher)

      {:ok, client_pid} = MLLP.Client.start_link({127, 0, 0, 1}, port)

      assert MLLP.Client.is_connected?(client_pid)

      MLLP.Receiver.stop(port)
      refute Process.alive?(receiver_pid)

      {:error, %Error{context: context, message: message}} =
        MLLP.Client.send(client_pid, "Simple message")

      assert context in [:sending, :receiving]
      assert message in [MLLP.Client.format_error(:closed), MLLP.Client.format_error(:einval)]

      refute MLLP.Client.is_connected?(client_pid)
    end

    test "with a larger message" do
      port = 8152

      {:ok, %{pid: _receiver_pid}} =
        MLLP.Receiver.start(
          port: port,
          dispatcher: ClientAndReceiverIntegrationTest.TestDispatcher
        )

      {:ok, client_pid} = MLLP.Client.start_link({127, 0, 0, 1}, port)

      message =
        (HL7.Examples.wikipedia_sample_hl7() <>
           "ZNK|JUNK|" <> String.pad_leading("\r", 10000, "Z"))
        |> HL7.Message.new()

      ack = MLLP.Client.send(client_pid, message)

      expected =
        {:ok, :application_accept,
         %MLLP.Ack{
           acknowledgement_code: "AA",
           hl7_ack_message: nil,
           text_message: ""
         }}

      assert expected == ack
    end
  end

  describe "timeout behaviour" do
    setup do
      Logger.configure(level: :debug)
      setup_receiver()
    end

    test "gen server call times out", %{port: port} = _ctx do
      {:ok, client_pid} = MLLP.Client.start_link({127, 0, 0, 1}, port, auto_reconnect_interval: 3)

      assert catch_exit(
               MLLP.Client.send(client_pid, "MSH|NOREPLY", %{reply_timeout: 2}, 1) == :timeout
             )

      # Wait for reconnect timer
      Process.sleep(2)
      assert Process.alive?(client_pid)
    end

    test "does not open additional sockets on reconnect", %{port: port} = _ctx do
      {:ok, client_pid} =
        MLLP.Client.start_link({127, 0, 0, 1}, port,
          auto_reconnect_interval: 3,
          close_on_recv_error: false
        )

      capture_log(fn ->
        {:error, %MLLP.Client.Error{reason: :timeout}} =
          MLLP.Client.send(client_pid, "MSH|NOREPLY", %{reply_timeout: 1})
      end)

      # Wait for reconnect timer
      Process.sleep(10)
      assert MLLP.Client.is_connected?(client_pid)
      {:ok, _} = MLLP.Client.send(client_pid, "MSH|REPLY")

      assert Enum.count(open_ports_for_pid(client_pid)) == 1
    end

    test "closes the socket, if close_on_recv_error set to true", %{port: port} = _ctx do
      {:ok, client_pid} =
        MLLP.Client.start_link({127, 0, 0, 1}, port,
          auto_reconnect_interval: 3,
          close_on_recv_error: true
        )

      {:error, _} = MLLP.Client.send(client_pid, "MSH|NOREPLY", %{reply_timeout: 1})
      Process.sleep(10)
      assert Enum.count(open_ports_for_pid(client_pid)) == 0
    end
  end

  describe "tls support" do
    setup ctx do
      transport_opts = %{
        tls: [
          cacertfile: "tls/root-ca/ca_certificate.pem",
          verify: :verify_none,
          certfile: "tls/server/server_certificate.pem",
          keyfile: "tls/server/private_key.pem"
        ]
      }

      {:ok, %{pid: receiver_pid}} =
        MLLP.Receiver.start(
          port: ctx.port,
          dispatcher: MLLP.EchoDispatcher,
          transport_opts: transport_opts
        )

      client_tls_options = [
        verify: :verify_peer,
        cacertfile: "tls/root-ca/ca_certificate.pem"
      ]

      on_exit(fn -> MLLP.Receiver.stop(ctx.port) end)

      [receiver_pid: receiver_pid, client_tls_options: client_tls_options]
    end

    @tag :tls
    @tag port: 8155
    test "can send to tls receiver", ctx do
      {:ok, client_pid} =
        MLLP.Client.start_link("localhost", ctx.port, tls: ctx.client_tls_options)

      assert ctx.ack ==
               MLLP.Client.send(
                 client_pid,
                 HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new()
               )
    end

    @tag :tls
    @tag port: 8156
    test "fails to connect to tls receiver with host name verification failure", ctx do
      {:ok, client_pid} =
        MLLP.Client.start_link({127, 0, 0, 1}, ctx.port, tls: ctx.client_tls_options)

      assert {:error, %Error{reason: {:tls_alert, {:handshake_failure, _}}, context: :sending}} =
               MLLP.Client.send(
                 client_pid,
                 HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new()
               )
    end

    @tag :tls
    @tag port: 8157
    test "can send to tls receiver without certificate with verify none option", ctx do
      {:ok, client_pid} =
        MLLP.Client.start_link("localhost", ctx.port, tls: [verify: :verify_none])

      assert ctx.ack ==
               MLLP.Client.send(
                 client_pid,
                 HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new()
               )
    end
  end

  describe "tls handshake failure logging" do
    setup do
      port = 4040

      transport_opts = %{
        tls: [
          cacertfile: "tls/root-ca/ca_certificate.pem",
          verify: :verify_none,
          certfile: "tls/server/server_certificate.pem",
          keyfile: "tls/server/private_key.pem",
          ssl_transport: MLLP.TLS.HandshakeLoggingTransport
        ]
      }

      {:ok, %{pid: receiver_pid}} =
        MLLP.Receiver.start(
          port: port,
          dispatcher: MLLP.EchoDispatcher,
          transport_opts: transport_opts
        )

      client_tls_options = [
        verify: :verify_peer,
        cacertfile: "tls/root-ca/ca_certificate.pem"
      ]

      on_exit(fn -> MLLP.Receiver.stop(port) end)

      [receiver_pid: receiver_pid, client_tls_options: client_tls_options, port: port]
    end

    test "handshake fails", ctx do
      assert capture_log(fn ->
               {:ok, client_pid} =
                 MLLP.Client.start_link({127, 0, 0, 1}, ctx.port, tls: ctx.client_tls_options)

               Process.sleep(10)
               refute MLLP.Client.is_connected?(client_pid)
             end) =~ "Handshake failure on connection attempt from {127, 0, 0, 1}"
    end
  end

  describe "ip restriction" do
    setup ctx do
      {:ok, %{pid: _receiver_pid}} =
        MLLP.Receiver.start(
          port: ctx.port,
          dispatcher: MLLP.EchoDispatcher,
          transport_opts: ctx.transport_opts,
          allowed_clients: ctx.allowed_clients
        )

      on_exit(fn -> MLLP.Receiver.stop(ctx.port) end)
    end

    @tag allowed_clients: ["127.0.0.0"]
    @tag port: 8158
    test "can restrict client if client IP is not allowed", ctx do
      {:ok, client_pid} = MLLP.Client.start_link("localhost", ctx.port)

      {:error, error} =
        MLLP.Client.send(
          client_pid,
          HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new()
        )

      assert error.context in [:sending, :receiving]
      assert error.reason in [:closed, :einval]
    end

    @tag allowed_clients: ["127.0.0.0", "localhost"]
    @tag port: 8159
    test "allow connection from allowed clients", ctx do
      {:ok, client_pid} = MLLP.Client.start_link("localhost", ctx.port)

      assert ctx.ack ==
               MLLP.Client.send(
                 client_pid,
                 HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new()
               )
    end

    @tag allowed_clients: [:localhost]
    @tag port: 8160
    test "atom is allowed as client ip or dns", ctx do
      {:ok, client_pid} = MLLP.Client.start_link("localhost", ctx.port)

      assert ctx.ack ==
               MLLP.Client.send(
                 client_pid,
                 HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new()
               )
    end
  end

  describe "client cert validation" do
    setup ctx do
      verify = ctx[:verify] || :verify_peer
      allowed_clients = ctx[:allowed_clients] || []

      tls_options = [
        cacertfile: "tls/root-ca/ca_certificate.pem",
        certfile: "tls/server/server_certificate.pem",
        keyfile: "tls/server/private_key.pem",
        verify: verify
      ]

      transport_opts = %{tls: tls_options}

      {:ok, %{pid: receiver_pid}} =
        MLLP.Receiver.start(
          port: ctx.port,
          dispatcher: ctx[:dispatcher] || MLLP.EchoDispatcher,
          transport_opts: transport_opts,
          allowed_clients: allowed_clients
        )

      client_cert = ctx[:client_cert] || "tls/client/client_certificate.pem"
      keyfile = ctx[:keyfile] || "tls/client/private_key.pem"

      client_tls_options = [
        verify: :verify_peer,
        cacertfile: "tls/root-ca/ca_certificate.pem",
        certfile: client_cert,
        keyfile: keyfile
      ]

      tls_alert = ctx[:reason] || []

      expected_error_reasons = [:einval, :no_socket, :closed] ++ tls_alert

      on_exit(fn -> MLLP.Receiver.stop(ctx.port) end)

      [
        receiver_pid: receiver_pid,
        client_tls_options: client_tls_options,
        expected_error_reasons: expected_error_reasons
      ]
    end

    @tag port: 8161
    @tag verify: :verify_none
    @tag client_cert: ""
    @tag keyfile: ""
    test "does not verify client cert if verify none option is provided on receiver", ctx do
      make_call_and_assert_success(ctx, ctx.ack)
    end

    @tag port: 8162
    @tag client_cert: ""
    @tag keyfile: ""

    @tag reason: [:handshake_failure, :certificate_required]
    test "no peer cert", ctx do
      make_call_and_assert_failure(ctx, ctx.expected_error_reasons)
    end

    @tag port: 8163
    test "accepts a peer cert", ctx do
      make_call_and_assert_success(ctx, ctx.ack)
    end

    @tag port: 8164
    @tag allowed_clients: ["client-1"]
    test "accepts peer cert for allowed client", ctx do
      make_call_and_assert_success(ctx, ctx.ack)
    end

    @tag port: 8165
    @tag allowed_clients: ["client-x", "client-y"]
    test "reject peer cert for unexpected clients", ctx do
      expected_error_reasons = [:einval, :closed]

      log =
        capture_log(fn ->
          make_call_and_assert_failure(ctx, expected_error_reasons)
        end)

      assert log =~ ":fail_to_verify_client_cert"
    end

    @tag port: 8166
    @tag client_cert: "tls/expired_client/client_certificate.pem"
    @tag keyfile: "tls/expired_client/private_key.pem"

    @tag reason: [:certificate_expired]
    test "reject expired peer cert", ctx do
      make_call_and_assert_failure(ctx, ctx.expected_error_reasons)
    end

    @tag port: 8167
    @tag client_cert: "tls/server/server_certificate.pem"
    @tag keyfile: "tls/server/private_key.pem"

    @tag reason: [:handshake_failure]
    test "reject server cert as peer cert", ctx do
      make_call_and_assert_failure(ctx, ctx.expected_error_reasons)
    end

    @tag port: 8168
    @tag allowed_clients: ["client-x", "client-1"]
    test "accept peer cert from multiple allowed clients", ctx do
      make_call_and_assert_success(ctx, ctx.ack)
    end

    @tag port: 8169, dispatcher: MLLP.DispatcherMock
    @tag allowed_clients: ["client-1"]
    test "returns client info in receiver context", ctx do
      ack =
        MLLP.Envelope.wrap_message(
          "MSH|^~\\&|||||20060529090131-0500||ACK^A01^ACK|01052901|P|2.5\rMSA|AA|01052901|A real MLLP message dispatcher was not provided\r"
        )

      MLLP.DispatcherMock
      |> expect(:dispatch, fn :mllp_hl7,
                              _msg,
                              %{receiver_context: %{connection_info: connection_info}} = state ->
        assert "client-1" == connection_info.peer_name

        {:ok, %{state | reply_buffer: ack}}
      end)

      make_call_and_assert_success(ctx, ctx.ack)
    end

    defp make_call_and_assert_success(ctx, expected_result) do
      assert expected_result == start_client_and_send(ctx)
    end

    defp make_call_and_assert_failure(ctx, expected_error_reasons) do
      reason =
        case start_client_and_send(ctx) do
          {:error, %Error{reason: {:tls_alert, {reason, _}}}} -> reason
          {:error, %Error{reason: reason}} -> reason
        end

      assert reason in expected_error_reasons
    end

    defp start_client_and_send(ctx) do
      {:ok, client_pid} =
        MLLP.Client.start_link("localhost", ctx.port, tls: ctx.client_tls_options)

      MLLP.Client.send(
        client_pid,
        HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new()
      )
    end
  end

  defmodule TestDispatcher do
    require Logger

    @behaviour MLLP.Dispatcher

    def dispatch(:mllp_hl7, <<"MSH|NOREPLY", _rest::binary>>, state) do
      {:ok, %{state | reply_buffer: ""}}
    end

    def dispatch(:mllp_hl7, message, state) when is_binary(message) do
      reply =
        MLLP.Ack.get_ack_for_message(
          message,
          :application_accept
        )
        |> to_string()
        |> MLLP.Envelope.wrap_message()

      {:ok, %{state | reply_buffer: reply}}
    end
  end

  defp open_ports_for_pid(pid) do
    Enum.filter(Port.list(), fn p ->
      info = Port.info(p)
      Keyword.get(info, :name) == 'tcp_inet' and Keyword.get(info, :connected) == pid
    end)
  end

  defp setup_receiver() do
    port = 4090

    {:ok, receiver} =
      MLLP.Receiver.start(port: port, dispatcher: ClientAndReceiverIntegrationTest.TestDispatcher)

    on_exit(fn ->
      try do
        MLLP.Receiver.stop(port)
      rescue
        _err -> :ok
      end
    end)

    %{receiver: receiver, port: port}
  end
end
