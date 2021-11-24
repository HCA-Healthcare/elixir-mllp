defmodule ReceiverTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  alias MLLP.{FramingContext, Receiver}
  require Logger

  doctest Receiver

  describe "Starting and stopping a receiver" do
    test "raises when no port argument provided" do
      assert_raise ArgumentError, fn ->
        Receiver.start([])
      end
    end

    test "raises when no dispatcher argument provided" do
      assert_raise ArgumentError, fn ->
        Receiver.start(port: 8130)
      end
    end

    test "creates and removes a receiver process" do
      port = 8130
      {:ok, %{pid: pid}} = Receiver.start(port: port, dispatcher: MLLP.DefaultDispatcher)

      assert Process.alive?(pid)

      :ok = Receiver.stop(port)
      refute Process.alive?(pid)
    end

    test "opens a port that can be connected to" do
      port = 8131
      {:ok, %{pid: pid}} = Receiver.start(port: port, dispatcher: MLLP.DefaultDispatcher)

      assert Process.alive?(pid)

      log =
        capture_log(fn ->
          tcp_connect_send_and_close(port, "Hello? Anyone there?")
          Process.sleep(100)
        end)

      assert log =~ "The DefaultPacketFramer is discarding unexpected data: Hello? Anyone there?"

      assert Process.alive?(pid)
      :ok = Receiver.stop(port)
    end

    test "on the same port twice returns error" do
      port = 8132
      {:ok, _} = Receiver.start(port: port, dispatcher: MLLP.DefaultDispatcher)

      assert capture_log(fn -> Receiver.start(port: port, dispatcher: MLLP.DefaultDispatcher) end) =~
               "port: 8132]) for reason :eaddrinuse (address already in use)"
    end
  end

  describe "Receiver accepts non-default framer" do
    test "non-default framer is given packets" do
      message = "<testing>123</testing>"

      test_pid = self()

      MLLP.PacketFramerMock
      |> expect(:handle_packet, fn ^message,
                                   %FramingContext{dispatcher_module: MLLP.DispatcherMock} = state ->
        Process.send(test_pid, :got_it, [])
        {:ok, state}
      end)

      port = 8133

      {:ok, %{pid: _pid}} =
        Receiver.start(
          port: port,
          dispatcher: MLLP.DispatcherMock,
          packet_framer: MLLP.PacketFramerMock
        )

      tcp_connect_send_and_close(port, message)
      assert_receive :got_it
    end
  end

  describe "Receiver receiving data" do
    test "frames and dispatches" do
      port = 8134
      {:ok, _} = Receiver.start(port: port, dispatcher: MLLP.DefaultDispatcher)

      msg = HL7.Examples.wikipedia_sample_hl7() |> MLLP.Envelope.wrap_message()

      capture_log(fn ->
        assert tcp_connect_send_receive_and_close(port, msg) =~ "MSA|AR|01052901"
      end)
    end

    test "via process mailbox discards unhandled messages" do
      port = 8135
      {:ok, %{pid: pid}} = Receiver.start(port: port, dispatcher: MLLP.DefaultDispatcher)
      assert Process.alive?(pid)

      log =
        capture_log(fn ->
          Process.send(pid, "junky junk", [])

          Process.sleep(100)
        end)

      assert log =~ "unexpected message: \"junky junk\""
    end

    test "opens a port that can be connected to by two senders" do
      port = 8136
      {:ok, %{pid: pid}} = Receiver.start(port: port, dispatcher: MLLP.DefaultDispatcher)

      log =
        capture_log(fn ->
          {:ok, sock1} =
            :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, {:packet, 0}, {:active, false}])

          {:ok, sock2} =
            :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, {:packet, 0}, {:active, false}])

          :ok = :gen_tcp.send(sock1, "AAAA")
          :ok = :gen_tcp.send(sock2, "BBBB")
          :ok = :gen_tcp.send(sock1, "CCCC")
          :ok = :gen_tcp.send(sock2, "DDDD")

          Process.sleep(100)
        end)

      assert log =~ "AAAA"
      assert log =~ "BBBB"
      assert log =~ "CCCC"
      assert log =~ "DDDD"

      assert Process.alive?(pid)
      :ok = Receiver.stop(port)
    end
  end

  defp tcp_connect_send_receive_and_close(port, data_to_send) do
    {:ok, sock} =
      :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, {:packet, 0}, {:active, false}])

    :ok = :gen_tcp.send(sock, data_to_send)

    {:ok, data} = :gen_tcp.recv(sock, 0, 1000)
    :ok = :gen_tcp.close(sock)
    data
  end

  defp tcp_connect_send_and_close(port, data_to_send) do
    {:ok, sock} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, {:packet, 0}])
    :ok = :gen_tcp.send(sock, data_to_send |> String.to_charlist())
    :ok = :gen_tcp.close(sock)
  end
end
