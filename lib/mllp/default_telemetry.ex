defmodule MLLP.DefaultTelemetry do
  def execute(event_name, measurements, metadata) do
    :telemetry.execute([:mllp] ++ event_name, measurements, metadata)
  end
end
