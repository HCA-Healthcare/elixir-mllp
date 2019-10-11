defmodule SenderTest do
  use ExUnit.Case
  alias MLLP.{Sender, Receiver}
  doctest Sender

  test "Integration: sending valid HL7 to a receiver works" do
    port = 8130
    {:ok, %{pid: pid}} = Receiver.start(port, SenderTest.TestDispatcher)

    {:ok, sender_pid} = Sender.start_link({{127, 0, 0, 1}, port})

    hl7 = HL7.Examples.wikipedia_sample_hl7()

    {:ok, :application_accept} = Sender.send_message(sender_pid, hl7)

    # todo how do i test the TestDispatcher.dispatch? -- create a target Agent?
    # todo verify message in receiver?

    :ok = MLLP.Receiver.stop(port)
    refute Process.alive?(pid)
  end

  test "Integration: sending valid HL7 with without ACK" do
    port = 8131
    {:ok, %{pid: pid}} = Receiver.start(port, SenderTest.TestDispatcher, false)
    {:ok, sender_pid} = Sender.start_link({{127, 0, 0, 1}, port})
    hl7 = HL7.Examples.wikipedia_sample_hl7()
    assert Sender.async_send_message(sender_pid, hl7) == :ok
    :ok = MLLP.Receiver.stop(port)
    refute Process.alive?(pid)
  end

  test "Integration: sending valid HL7 with no receiver" do
    port = 8131

    {:ok, sender_pid} = Sender.start_link({{127, 0, 0, 1}, port})

    hl7 = HL7.Examples.wikipedia_sample_hl7()

    {:ok, :application_error} = Sender.send_message(sender_pid, hl7)
  end

  test "Integration: sending invalid HL7 to a receiver returns application reject" do
    port = 8132
    {:ok, %{pid: pid}} = Receiver.start(port)

    {:ok, sender_pid} = Sender.start_link({{127, 0, 0, 1}, port})

    hl7 = "BAD DATA!!!"

    {:ok, :application_reject} = Sender.send_message(sender_pid, hl7)

    :ok = MLLP.Receiver.stop(port)
    refute Process.alive?(pid)
  end

  test "Stopping a sender" do
    port = 8133
    {:ok, sender_pid} = Sender.start_link({{127, 0, 0, 1}, port})

    assert Process.alive?(sender_pid)

    Sender.stop(sender_pid)

    assert Process.alive?(sender_pid) == false
  end

  defmodule TestDispatcher do
    require Logger

    @behaviour MLLP.Dispatcher

    def dispatch(message) when is_binary(message) do
      Logger.warn(fn -> "Test dispatcher handles: #{inspect(message)}" end)
      {:ok, :application_accept}
    end

    def dispatch(message) do
      Logger.warn("Test dispatcher rejects non-string message: #{inspect(message)}")

      {:ok, :application_reject}
    end
  end
end
