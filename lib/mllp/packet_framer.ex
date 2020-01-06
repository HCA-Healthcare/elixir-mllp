defmodule MLLP.PacketFramer do
  @callback handle_packet(packet :: String.t(), state :: MLLP.FramingContext.t()) ::
              {:ok, MLLP.FramingContext.t()}

  def get_mllp_message_type("MSH" <> _rest_of_message), do: :mllp_hl7
  def get_mllp_message_type(_message), do: :mllp_unknown

  defmacro __using__(opts) do
    {opt_frame_types, _} =
      opts
      |> Keyword.get(:frame_types, [])
      # It is said that using this function in a macro is bad,
      # but I can't figure out another way to make it work.
      |> Code.eval_quoted()

    # ^K - VT (Vertical Tab)
    mllp_start_of_block = <<0x0B>>
    mllp_end_of_block = <<0x1C, 0x0D>>

    frame_types =
      opt_frame_types
      |> Enum.concat([
        {mllp_start_of_block, mllp_end_of_block, unquote(&__MODULE__.get_mllp_message_type/1)}
      ])

    quote do
      @behaviour MLLP.PacketFramer

      @doc false
      @spec handle_packet(packet :: String.t(), state :: MLLP.FramingContext.t()) ::
              {:ok, MLLP.FramingContext.t()}

      unquote do
        frame_types
        |> Enum.map(fn {start_of_block, end_of_block, message_type} ->
          quote do
            def handle_packet(
                  unquote(start_of_block) <> rest_of_packet,
                  state
                ) do
              case String.split(rest_of_packet, unquote(end_of_block), parts: 2) do
                [receiver_buffer] ->
                  {:ok, %{state | receiver_buffer: unquote(start_of_block) <> receiver_buffer}}

                [message, receiver_buffer] ->
                  message_type_atom =
                    unquote(message_type)
                    |> get_message_type(message)

                  {:ok, new_state} =
                    state.dispatcher_module.dispatch(message_type_atom, message, %{
                      state
                      | receiver_buffer: receiver_buffer
                    })

                  if receiver_buffer == "" do
                    {:ok, new_state}
                  else
                    handle_packet(receiver_buffer, new_state)
                  end
              end
            end
            |> inspect(label: "quote")
          end
        end)
      end

      @doc false
      @spec get_message_type(message_type :: atom() | fun(), message :: String.t()) :: atom()
      def(get_message_type(message_type, _message) when is_atom(message_type)) do
        message_type
      end

      def get_message_type(message_type, message) when is_function(message_type) do
        message_type.(message)
      end
    end
  end
end
