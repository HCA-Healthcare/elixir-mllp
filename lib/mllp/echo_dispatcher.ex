defmodule MLLP.EchoDispatcher do
  @moduledoc """
  Echo dispatcher informs the user that a dispatch function was not set and returns an application_accept
  or application_reject depending on if the message is valid (String) or not. Useful for debugging and serves
  as an example for writing your own dispatcher. 
  """

  require Logger

  @behaviour MLLP.Dispatcher

  @spec dispatch(:mllp_hl7, binary(), MLLP.FramingContext.t()) :: {:ok, MLLP.FramingContext.t()}
  def dispatch(:mllp_hl7, message, state) when is_binary(message) do
    Logger.info(
      "The EchoDispatcher simply logs and discards messages. Message type: mllp_hl7 Message: #{message}"
    )

    reply =
      MLLP.Ack.get_ack_for_message(
        message,
        :application_reject,
        "A real MLLP message dispatcher was not provided"
      )
      |> to_string()
      |> MLLP.Envelope.wrap_message()

    {:ok, %{state | reply_buffer: reply}}
  end
end
