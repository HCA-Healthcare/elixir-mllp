defmodule MLLP.EchoDispatcher do
  @moduledoc """
  Echo dispatcher informs the user that a dispatch function was not set and returns an application_accept
  or application_reject depending on if the message is valid (String) or not. Useful for debugging and serves
  as an example for writing your own dispatcher. 
  """

  require Logger

  @behaviour MLLP.Dispatcher

  @spec dispatch(:mllp_hl7 | :mllp_unknown, binary(), MLLP.FramingContext.t()) ::
          {:ok, MLLP.FramingContext.t()}
  def dispatch(:mllp_unknown, _, state) do
    msg = MLLP.Envelope.wrap_message("mllp_unknown")
    {:ok, %{state | reply_buffer: msg}}
  end

  def dispatch(:mllp_hl7, message, state) when is_binary(message) do
    Logger.info(
      "The EchoDispatcher simply logs and discards messages. Message type: :mllp_hl7 Message: #{message}"
    )

    {:ok, %{state | reply_buffer: reply_for(message)}}
  end

  defp reply_for(message) do
    {msg, type} = new_hl7(message)

    msg
    |> MLLP.Ack.get_ack_for_message(type, "A real MLLP message dispatcher was not provided")
    |> to_string()
    |> MLLP.Envelope.wrap_message()
  end

  defp new_hl7(message) do
    case HL7.Message.new(message) do
      %HL7.InvalidMessage{} = msg ->
        {msg, :application_reject}

      %HL7.Message{} = msg ->
        {msg, :application_accept}
    end
  end
end
