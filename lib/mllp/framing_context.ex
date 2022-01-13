defmodule MLLP.FramingContext do
  defstruct receiver_buffer: "",
            reply_buffer: "",
            current_message_type: nil,
            packet_framer_module: MLLP.DefaultPacketFramer,
            dispatcher_module: nil,
            receiver_context: %{}

  @type t :: %__MODULE__{
          receiver_buffer: String.t(),
          reply_buffer: String.t(),
          current_message_type: atom(),
          packet_framer_module: atom,
          dispatcher_module: atom,
          receiver_context: map()
        }
end
