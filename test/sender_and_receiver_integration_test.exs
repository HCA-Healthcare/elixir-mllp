defmodule SenderAndReceiverIntegrationTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  describe "Starting and stopping" do
    test "with a listener listening" do
      port = 8143

      {:ok, %{pid: receiver_pid}} = MLLP.Receiver.start(port)
      assert Process.alive?(receiver_pid)

      {:ok, sender_pid} = MLLP.Sender.start_link({{127, 0, 0, 1}, port})
      assert Process.alive?(sender_pid)

      assert MLLP.Sender.is_connected?(sender_pid)

      capture_log(fn -> MLLP.Sender.stop(sender_pid) end)
      assert Process.alive?(sender_pid) == false

      MLLP.Receiver.stop(port)
      assert Process.alive?(receiver_pid) == false
    end

    test "without a listener" do
      port = 8143

      {:ok, sender_pid} = MLLP.Sender.start_link({{127, 0, 0, 1}, port})
      assert Process.alive?(sender_pid)

      assert MLLP.Sender.is_connected?(sender_pid) == false

      capture_log(fn -> MLLP.Sender.stop(sender_pid) end)
      assert Process.alive?(sender_pid) == false
    end

    test "with a listener added late" do
      port = 8145

      {:ok, sender_pid} = MLLP.Sender.start_link({{127, 0, 0, 1}, port})
      assert Process.alive?(sender_pid)

      assert MLLP.Sender.is_connected?(sender_pid) == false

      {:ok, %{pid: receiver_pid}} = MLLP.Receiver.start(port)
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

      {:ok, sender_pid} = MLLP.Sender.start_link({{127, 0, 0, 1}, port})
      assert Process.alive?(sender_pid)

      payload = "A simple message"

      assert {:error, :not_connected} == MLLP.Sender.send_raw(sender_pid, payload)

      capture_log(fn -> MLLP.Sender.stop(sender_pid) end)
      assert Process.alive?(sender_pid) == false
    end

    @tag :skip
    test "with a listener that stops before the send" do
      port = 8151

      {:ok, %{pid: receiver_pid}} = MLLP.Receiver.start(port)

      {:ok, sender_pid} = MLLP.Sender.start_link({{127, 0, 0, 1}, port})

      MLLP.Receiver.stop(port)
      assert Process.alive?(receiver_pid) == false
      assert "???" == MLLP.Sender.send_raw(sender_pid, "Simple message")
    end
  end
end
