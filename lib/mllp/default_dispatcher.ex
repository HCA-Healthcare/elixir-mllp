defmodule MLLP.DefaultDispatcher do
  require Logger

  @behaviour MLLP.Dispatcher

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
