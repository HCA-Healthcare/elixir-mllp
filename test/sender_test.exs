defmodule SenderTest do
  use ExUnit.Case
  alias MLLP.{Sender, Receiver}
  doctest Sender

  test "Integration: sending valid HL7 to a receiver works" do
    port = 8130
    {:ok, %{pid: pid}} = Receiver.start(port)

    {:ok, sender_pid} = Sender.start_link({{127, 0, 0, 1}, port})
    Sender.connect(sender_pid)

    hl7 = HL7.Examples.wikipedia_sample_hl7()

    {:ok, :application_accept} = Sender.send_message(sender_pid, hl7)

    :ok = MLLP.Receiver.stop(port)
    refute Process.alive?(pid)
  end
end
