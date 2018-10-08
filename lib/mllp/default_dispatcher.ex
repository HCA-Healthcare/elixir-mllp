defmodule MLLP.DefaultDispatcher do
  require Logger

  @behaviour MLLP.Dispatcher

  def dispatch(message) when is_binary(message) do
    Logger.debug(
      "MLLP dispatcher function not set. Default logs and discards message. Message: #{message}"
    )

    {:ok, :application_accept}
  end
end
