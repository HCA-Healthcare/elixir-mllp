defmodule DefaultDispatcherTest do
  use ExUnit.Case
  alias MLLP.DefaultDispatcher
  doctest DefaultDispatcher

  import ExUnit.CaptureLog

  test "Default dispatcher accepts HL7, logs, and returns application_reject" do
    state = %MLLP.FramingContext{}
    message = HL7.Examples.wikipedia_sample_hl7()

    expected_reply =
      MLLP.Ack.get_ack_for_message(
        message,
        :application_reject,
        "A real MLLP message dispatcher was not provided"
      )
      |> to_string()
      |> MLLP.Envelope.wrap_message()

    expected_state = %{state | reply_buffer: expected_reply}

    log =
      capture_log(fn ->
        assert {:ok, expected_state} == DefaultDispatcher.dispatch(:mllp_hl7, message, state)
      end)

    assert log =~ "The DefaultDispatcher simply logs and discards messages"
  end
end
