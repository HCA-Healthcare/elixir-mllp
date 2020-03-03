defmodule MLLP.Dispatcher do
  @callback dispatch(
              message_type :: atom(),
              message :: String.t(),
              state :: MLLP.FramingContext.t()
            ) ::
              {:ok, state :: MLLP.FramingContext.t()}
end
