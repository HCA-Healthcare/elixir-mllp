defmodule MLLP.Logger do
  @moduledoc """
  Provides logging functionality that maintains messages format.
  """
  require Logger

  @spec info(String.t(), any(), Keyword.t()) :: :ok
  def info(message, reason \\ nil, data \\ []) do
    Logger.info(fn -> compose_message(message, reason, data) end)
  end

  @spec error(String.t(), any(), Keyword.t()) :: :ok
  def error(message, reason \\ nil, data \\ []) do
    Logger.error(fn -> compose_message(message, reason, data) end)
  end

  @spec warn(String.t(), any(), Keyword.t()) :: :ok
  def warn(message, reason \\ nil, data \\ []) do
    Logger.warn(fn -> compose_message(message, reason, data) end)
  end

  @spec debug(String.t(), any(), Keyword.t()) :: :ok
  def debug(message, reason \\ nil, data \\ []) do
    Logger.debug(fn -> compose_message(message, reason, data) end)
  end

  defp compose_message(message, nil, data) do
    "[MLLP] #{message}" <> parse_data(data)
  end

  defp compose_message(message, reason, data) do
    "[MLLP] #{message}: " <> parse_value(reason) <> parse_data(data)
  end

  defp parse_value(value) when is_binary(value), do: "#{value}"
  defp parse_value(value), do: "#{inspect(value)}"

  defp parse_data([]), do: ""

  defp parse_data(data) do
    count = length(data)

    {data, _} =
      Enum.reduce(data, {" -", 1}, fn
        {k, v}, {str, ^count} ->
          {str <> " #{k}: #{parse_value(v)}", count}

        {k, v}, {str, r} ->
          {str <> " #{k}: #{parse_value(v)},", r + 1}
      end)

    data
  end
end
