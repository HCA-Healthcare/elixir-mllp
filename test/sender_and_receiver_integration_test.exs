defmodule SenderAndReceiverIntegrationTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  describe "Supervsion" do
    test "successfully starts up under a supervisor using a child spec" do
      port = 8999
      transport_opts = %{num_acceptors: 1, max_connections: 1, socket_opts: [delay_send: true]}

      opts = [
        ref: ReceiverSupervisionTest,
        port: port,
        transport_opts: transport_opts,
        dispatcher: MLLP.DefaultDispatcher
      ]

      pid = start_supervised!({MLLP.Receiver, opts})
      sup_children = Supervisor.which_children(pid)

      assert [
               {:ranch_acceptors_sup, _acceptor_pid, :supervisor, [:ranch_acceptors_sup]},
               {:ranch_conns_sup, conns_pid, :supervisor, [:ranch_conns_sup]}
             ] = sup_children

      {:ok, sender_pid} = MLLP.Sender.start_link({127, 0, 0, 1}, port)

      message = MLLP.Envelope.wrap_message(HL7.Examples.wikipedia_sample_hl7())

      capture_log(fn ->
        assert {:ok, _msg} = MLLP.Sender.send_raw_and_receive_reply(sender_pid, message)
      end)

      assert [{MLLP.Receiver, _pid, :worker, [MLLP.Receiver]}] =
               Supervisor.which_children(conns_pid)
    end

    test "child_spec/1 accepts and returns documented options" do
      port = 8999
      transport_opts = %{num_acceptors: 1, max_connections: 1, socket_opts: [delay_send: true]}

      opts = [
        ref: ReceiverSupervisionTest,
        port: port,
        transport_opts: transport_opts,
        dispatcher: MLLP.DefaultDispatcher
      ]

      expected_spec = %{
        id: {:ranch_listener_sup, ReceiverSupervisionTest},
        modules: [:ranch_listener_sup],
        restart: :permanent,
        shutdown: :infinity,
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
               dispatcher_module: MLLP.DefaultDispatcher
             ]
           ]},
        type: :supervisor
      }

      assert MLLP.Receiver.child_spec(opts) == expected_spec
    end
  end

  describe "Starting and stopping" do
    test "with a listener listening" do
      port = 8143

      {:ok, %{pid: receiver_pid}} =
        MLLP.Receiver.start(port: port, dispatcher: MLLP.DefaultDispatcher)

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
        MLLP.Receiver.start(port: port, dispatcher: MLLP.DefaultDispatcher)

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
        MLLP.Receiver.start(port: port, dispatcher: MLLP.DefaultDispatcher)

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
