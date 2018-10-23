defmodule SenderTest do
  use ExUnit.Case
  alias MLLP.{Sender, Receiver}
  doctest Sender

  test "Integration: sending valid HL7 to a receiver works" do
    port = 8130
    {:ok, %{pid: pid}} = Receiver.start(port)

    {:ok, sender_pid} = Sender.start_link({{127, 0, 0, 1}, port})

    hl7 = HL7.Examples.wikipedia_sample_hl7()

    {:ok, :application_accept} = Sender.send_message(sender_pid, hl7)

    # todo verify message in receiver?

    :ok = MLLP.Receiver.stop(port)
    refute Process.alive?(pid)
  end

  test "Integration: sending valid HL7 with no receiver" do
    port = 8131

    {:ok, sender_pid} = Sender.start_link({{127, 0, 0, 1}, port})

    hl7 = HL7.Examples.wikipedia_sample_hl7()

    {:ok, :application_error} = Sender.send_message(sender_pid, hl7)
  end

  test "Integration: sending invalid HL7 to a receiver return application reject" do
    port = 8132
    {:ok, %{pid: pid}} = Receiver.start(port)

    {:ok, sender_pid} = Sender.start_link({{127, 0, 0, 1}, port})

    hl7 = "BAD DATA!!!"

    {:ok, :application_reject} = Sender.send_message(sender_pid, hl7)

    :ok = MLLP.Receiver.stop(port)
    refute Process.alive?(pid)
  end
end
