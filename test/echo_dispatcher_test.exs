defmodule EchoDispatcherTest do
  use ExUnit.Case
  alias MLLP.EchoDispatcher
  doctest EchoDispatcher

  test "Echo dispatcher accepts HL7, logs, and returns application_accept" do
    state = %MLLP.FramingContext{}
    message = HL7.Examples.wikipedia_sample_hl7()

    expected_reply =
      MLLP.Ack.get_ack_for_message(
        message,
        :application_accept,
        "A real MLLP message dispatcher was not provided"
      )
      |> to_string()
      |> MLLP.Envelope.wrap_message()

    expected_state = %{state | reply_buffer: expected_reply}

    assert {:ok, expected_state} == EchoDispatcher.dispatch(:mllp_hl7, message, state)
  end

  test "Echo dispatcher accepts HL7, logs, and returns application_reject" do
    state = %MLLP.FramingContext{}
    message = "eh?"

    MLLP.Ack.get_ack_for_message(
      HL7.Message.new("eh?"),
      :application_reject,
      "A real MLLP message dispatcher was not provided"
    )
    |> to_string()
    |> MLLP.Envelope.wrap_message()

    # expected_state = %{state | reply_buffer: expected_reply}

    assert {:ok, state1} = EchoDispatcher.dispatch(:mllp_unknown, message, state)
    assert state1.reply_buffer =~ "|P|2.5\rMSA|AR|"
  end
end
