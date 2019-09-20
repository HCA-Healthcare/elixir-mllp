defmodule MLLP.Dispatcher do
  @callback dispatch(message :: binary) ::
              {:ok, :application_accept | :application_reject | :application_error}
end
