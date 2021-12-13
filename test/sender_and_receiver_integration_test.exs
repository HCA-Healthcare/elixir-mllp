defmodule SenderAndReceiverIntegrationTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  @moduletag capture_log: true

  setup ctx do
    ack = {
      :error,
      :application_reject,
      %MLLP.Ack{
        acknowledgement_code: "AR",
        hl7_ack_message: nil,
        text_message: "A real MLLP message dispatcher was not provided"
      }
    }

    transport_opts = ctx[:transport_opts] || %{}
    allowed_clients = ctx[:allowed_clients] || []
    port = ctx[:port] || 9000

    [ack: ack, port: port, transport_opts: transport_opts, allowed_clients: allowed_clients]
  end

  describe "Supervsion" do
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

      {:ok, sender_pid} = MLLP.Sender.start_link({127, 0, 0, 1}, port)

      message = MLLP.Envelope.wrap_message(HL7.Examples.wikipedia_sample_hl7())

      capture_log(fn ->
        assert {:ok, _msg} = MLLP.Sender.send_raw_and_receive_reply(sender_pid, message)
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
             [
               packet_framer_module: MLLP.DefaultPacketFramer,
               dispatcher_module: MLLP.EchoDispatcher,
               allowed_clients: [],
               verify_peer: false
             ]
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

      {:ok, sender_pid} = MLLP.Sender.start_link({127, 0, 0, 1}, port)
      assert Process.alive?(sender_pid)

      assert MLLP.Sender.is_connected?(sender_pid)

      capture_log(fn -> MLLP.Sender.stop(sender_pid) end)
      assert Process.alive?(sender_pid) == false

      MLLP.Receiver.stop(port)
      assert Process.alive?(receiver_pid) == false
    end

    test "without a listener" do
      port = 8144

      {:ok, sender_pid} = MLLP.Sender.start_link({127, 0, 0, 1}, port)
      assert Process.alive?(sender_pid)

      assert MLLP.Sender.is_connected?(sender_pid) == false

      capture_log(fn -> MLLP.Sender.stop(sender_pid) end)
      assert Process.alive?(sender_pid) == false
    end

    test "with a listener added late" do
      port = 8145

      {:ok, sender_pid} = MLLP.Sender.start_link({127, 0, 0, 1}, port)
      assert Process.alive?(sender_pid)

      assert MLLP.Sender.is_connected?(sender_pid) == false

      {:ok, %{pid: receiver_pid}} =
        MLLP.Receiver.start(port: port, dispatcher: MLLP.EchoDispatcher)

      assert Process.alive?(receiver_pid)

      MLLP.Sender.reconnect(sender_pid)
      assert MLLP.Sender.is_connected?(sender_pid) == false

      capture_log(fn -> MLLP.Sender.stop(sender_pid) end)
      assert Process.alive?(sender_pid) == false

      MLLP.Receiver.stop(port)
      assert Process.alive?(receiver_pid) == false
    end
  end

  describe "Sending and receiving" do
    test "without a listener listening" do
      port = 8150

      {:ok, sender_pid} = MLLP.Sender.start_link({127, 0, 0, 1}, port)
      assert Process.alive?(sender_pid)

      payload = "A simple message"

      assert {:error, %{type: :connect_failure, reason: :no_socket}} ==
               MLLP.Sender.send_raw(sender_pid, payload)

      capture_log(fn -> MLLP.Sender.stop(sender_pid) end)
      assert Process.alive?(sender_pid) == false
    end

    test "with a receiver that stops before the send" do
      port = 8151

      {:ok, %{pid: receiver_pid}} =
        MLLP.Receiver.start(port: port, dispatcher: MLLP.EchoDispatcher)

      {:ok, sender_pid} = MLLP.Sender.start_link({127, 0, 0, 1}, port)

      MLLP.Receiver.stop(port)
      assert Process.alive?(receiver_pid) == false

      assert {:error, %{type: :recv_failure, reason: :closed}} ==
               MLLP.Sender.send_raw_and_receive_reply(sender_pid, "Simple message")
    end

    test "with a larger message" do
      port = 8152

      {:ok, %{pid: _receiver_pid}} =
        MLLP.Receiver.start(
          port: port,
          dispatcher: SenderAndReceiverIntegrationTest.TestDispatcher
        )

      {:ok, sender_pid} = MLLP.Sender.start_link({127, 0, 0, 1}, port)

      message =
        (HL7.Examples.wikipedia_sample_hl7() <>
           "ZNK|JUNK|" <> String.pad_leading("\r", 10000, "Z"))
        |> HL7.Message.new()

      ack = MLLP.Sender.send_hl7_and_receive_ack(sender_pid, message)

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
    test "does not open additional sockets on reconnect" do
      port = 8153

      {:ok, %{pid: _receiver_pid}} =
        MLLP.Receiver.start(
          port: port,
          dispatcher: SenderAndReceiverIntegrationTest.TestDispatcher
        )

      {:ok, sender_pid} = MLLP.Sender.start_link({127, 0, 0, 1}, port)

      message =
        (HL7.Examples.wikipedia_sample_hl7() <>
           "ZNK|JUNK|" <> String.pad_leading("\r", 100, "Z"))
        |> HL7.Message.new()
        |> to_string()

      capture_log(fn ->
        {:error, _} = MLLP.Sender.send_raw_and_receive_reply(sender_pid, message, 10)
      end)

      # Wait for reconnect timer
      Process.sleep(1500)
      assert Process.alive?(sender_pid)

      assert Enum.count(open_ports_for_pid(sender_pid)) == 1
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

      sender_tls_options = [
        verify: :verify_peer,
        cacertfile: "tls/root-ca/ca_certificate.pem"
      ]

      on_exit(fn -> MLLP.Receiver.stop(ctx.port) end)

      [receiver_pid: receiver_pid, sender_tls_options: sender_tls_options]
    end

    @tag :tls
    @tag port: 8154
    test "can send to tls receiver", ctx do
      {:ok, sender_pid} =
        MLLP.Sender.start_link("localhost", ctx.port, tls: ctx.sender_tls_options)

      assert ctx.ack ==
               MLLP.Sender.send_hl7_and_receive_ack(
                 sender_pid,
                 HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new()
               )
    end

    @tag :tls
    @tag port: 8155
    test "fails to connect to tls receiver with host name verification failure", ctx do
      {:ok, sender_pid} =
        MLLP.Sender.start_link({127, 0, 0, 1}, ctx.port, tls: ctx.sender_tls_options)

      assert {:error, %{reason: :no_socket, type: :connect_failure}} ==
               MLLP.Sender.send_hl7_and_receive_ack(
                 sender_pid,
                 HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new()
               )
    end

    @tag :tls
    @tag port: 8156
    test "can send to tls receiver without certificate with verify none option", ctx do
      {:ok, sender_pid} =
        MLLP.Sender.start_link("localhost", ctx.port, tls: [verify: :verify_none])

      assert ctx.ack ==
               MLLP.Sender.send_hl7_and_receive_ack(
                 sender_pid,
                 HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new()
               )
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
    @tag port: 8157
    test "can restrict client if client IP is not allowed", ctx do
      {:ok, sender_pid} = MLLP.Sender.start_link("localhost", ctx.port)

      assert {:error, %{reason: :closed, type: :recv_failure}} ==
               MLLP.Sender.send_hl7_and_receive_ack(
                 sender_pid,
                 HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new()
               )
    end

    @tag allowed_clients: ["127.0.0.0", "localhost"]
    @tag port: 8158
    test "allow connection from allowed clients", ctx do
      {:ok, sender_pid} = MLLP.Sender.start_link("localhost", ctx.port)

      assert ctx.ack ==
               MLLP.Sender.send_hl7_and_receive_ack(
                 sender_pid,
                 HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new()
               )
    end

    @tag allowed_clients: [:localhost]
    @tag port: 8159
    test "atom is allowed as client ip or dns", ctx do
      {:ok, sender_pid} = MLLP.Sender.start_link("localhost", ctx.port)

      assert ctx.ack ==
               MLLP.Sender.send_hl7_and_receive_ack(
                 sender_pid,
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

      transport_opts = %{
        tls: Keyword.put_new(tls_options, :verify, verify)
      }

      {:ok, %{pid: receiver_pid}} =
        MLLP.Receiver.start(
          port: ctx.port,
          dispatcher: MLLP.EchoDispatcher,
          transport_opts: transport_opts,
          allowed_clients: allowed_clients
        )

      client_cert = ctx[:client_cert] || "tls/client/client_certificate.pem"
      keyfile = ctx[:keyfile] || "tls/client/private_key.pem"

      sender_tls_options = [
        verify: :verify_peer,
        cacertfile: "tls/root-ca/ca_certificate.pem",
        certfile: client_cert,
        keyfile: keyfile
      ]

      tls_alert = {:tls_alert, ctx[:reason]}

      expected_error_reasons = [:einval, :closed, tls_alert]

      on_exit(fn -> MLLP.Receiver.stop(ctx.port) end)

      [
        receiver_pid: receiver_pid,
        sender_tls_options: sender_tls_options,
        expected_error_reasons: expected_error_reasons
      ]
    end

    @tag port: 8160
    @tag verify: :verify_none
    @tag client_cert: ""
    @tag keyfile: ""
    test "does not verify client cert if verify none option is provided on receiver", ctx do
      make_call_and_assert_success(ctx, ctx.ack)
    end

    @tag port: 8161
    @tag client_cert: ""
    @tag keyfile: ""
    @tag reason:
           {:certificate_required,
            'TLS client: In state connection received SERVER ALERT: Fatal - Certificate required\n'}
    test "no peer cert", ctx do
      make_call_and_assert_failure(ctx, ctx.expected_error_reasons)
    end

    @tag port: 8162
    test "accepts a peer cert", ctx do
      make_call_and_assert_success(ctx, ctx.ack)
    end

    @tag port: 8163
    @tag allowed_clients: ["client-1"]
    test "accepts peer cert for allowed client", ctx do
      make_call_and_assert_success(ctx, ctx.ack)
    end

    @tag port: 8163
    @tag allowed_clients: ["client-x", "client-y"]
    test "reject peer cert for unexpected clients", ctx do
      expected_error_reasons = [:closed]

      log =
        capture_log(fn ->
          make_call_and_assert_failure(ctx, expected_error_reasons)
        end)

      assert log =~ ":fail_to_verify_client_cert"
    end

    @tag port: 8163
    @tag client_cert: "tls/expired_client/client_certificate.pem"
    @tag keyfile: "tls/expired_client/private_key.pem"
    @tag reason:
           {:certificate_expired,
            'TLS client: In state connection received SERVER ALERT: Fatal - Certificate Expired\n'}

    test "reject expired peer cert", ctx do
      make_call_and_assert_failure(ctx, ctx.expected_error_reasons)
    end

    @tag port: 8163
    @tag client_cert: "tls/server/server_certificate.pem"
    @tag keyfile: "tls/server/private_key.pem"
    @tag reason:
           {:handshake_failure,
            'TLS client: In state connection received SERVER ALERT: Fatal - Handshake Failure\n'}

    test "reject server cert as peer cert", ctx do
      make_call_and_assert_failure(ctx, ctx.expected_error_reasons)
    end

    @tag port: 8164
    @tag allowed_clients: ["client-x", "client-1"]
    test "accept peer cert from multiple allowed clients", ctx do
      make_call_and_assert_success(ctx, ctx.ack)
    end

    defp make_call_and_assert_success(ctx, expected_result) do
      assert expected_result == start_sender_and_send(ctx)
    end

    defp make_call_and_assert_failure(ctx, expected_error_reasons) do
      {:error, %{reason: reason, type: _}} = start_sender_and_send(ctx)
      assert reason in expected_error_reasons
    end

    defp start_sender_and_send(ctx) do
      {:ok, sender_pid} =
        MLLP.Sender.start_link("localhost", ctx.port, tls: ctx.sender_tls_options)

      MLLP.Sender.send_hl7_and_receive_ack(
        sender_pid,
        HL7.Examples.wikipedia_sample_hl7() |> HL7.Message.new()
      )
    end
  end

  defmodule TestDispatcher do
    require Logger

    @behaviour MLLP.Dispatcher

    def dispatch(:mllp_hl7, message, state) when is_binary(message) do
      reply =
        MLLP.Ack.get_ack_for_message(
          message,
          :application_accept
        )
        |> to_string()

      {:ok, %{state | reply_buffer: reply}}
    end
  end

  defp open_ports_for_pid(pid) do
    Enum.filter(Port.list(), fn p ->
      info = Port.info(p)
      Keyword.get(info, :name) == 'tcp_inet' and Keyword.get(info, :connected) == pid
    end)
  end
end
