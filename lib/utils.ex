defmodule MLLP.Utils do
  require Logger
  @log_prefix "ELIXIR-MLLP :: "
  def log(level, message) do
    Logger.log(level, format_message(message))
  end

  defp format_message(message) when is_binary(message) do
    @log_prefix <> message
  end

  defp format_message(message) do
    @log_prefix <> inspect(message)
  end
end
