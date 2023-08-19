defmodule MLLP.Utils do
  require Logger

  def log(level, message, prefix \\ nil) do
    Logger.log(level, format_message(message, prefix))
  end

  defp format_message(message, prefix) do
    if prefix do
      "#{inspect(prefix)} :: " <> message
    else
      message
    end
  end
end
