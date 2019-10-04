defmodule MLLP.DefaultDispatcher do
  require Logger

  @behaviour MLLP.Dispatcher

  @moduledoc """
  Default dispatcher informs user that a dispatch function was not set and returns an application_accept
  or application_reject depending on if the message is valid (String) or not.
  """
  @spec dispatch(binary()) :: {:ok, :application_accept | :application_reject}
  def dispatch(message) when is_binary(message) do
    Logger.warn(
      "MLLP dispatcher function not set. Default logs and discards message. Message: #{message}"
    )

    {:ok, :application_accept}
  end

  def dispatch(message) do
    Logger.warn(
      "MLLP dispatcher function not set. Default logs and discards message. Rejecting non-string message: #{
        inspect(message)
      }"
    )

    {:ok, :application_reject}
  end
end
