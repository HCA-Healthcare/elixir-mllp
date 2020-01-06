defmodule MLLP.FramingContext do
  defstruct receiver_buffer: "",
            reply_buffer: "",
            packet_framer_module: MLLP.DefaultPacketFramer,
            dispatcher_module: MLLP.DefaultDispatcher,
            custom_data: %{}

  @type t :: %__MODULE__{
          receiver_buffer: String.t(),
          reply_buffer: String.t(),
          packet_framer_module: atom,
          dispatcher_module: atom,
          custom_data: map()
        }
end
