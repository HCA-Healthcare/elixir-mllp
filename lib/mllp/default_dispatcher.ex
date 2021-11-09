defmodule MLLP.DefaultDispatcher do
  @moduledoc """
  Default dispatcher informs user that a dispatch function was not set and returns an application_accept
  or application_reject depending on if the message is valid (String) or not.
  """

  require Logger

  @behaviour MLLP.Dispatcher

  @spec dispatch(:mllp_hl7, binary(), MLLP.FramingContext.t()) :: {:ok, MLLP.FramingContext.t()}
  def dispatch(:mllp_hl7, message, state) when is_binary(message) do
    Logger.error(
      "MLLP.Dispatcher not set. The DefaultDispatcher simply logs and discards messages. Message type: mllp_hl7 Message: #{message}"
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
