defmodule MLLP.PacketFramer do
  @callback handle_packet(packet :: String.t(), state :: MLLP.FramingContext.t()) ::
              {:ok, MLLP.FramingContext.t()}

  defmacro __using__(opts) do
    alias MLLP.FramingContext

    {opt_frame_types, _} =
      opts
      |> Keyword.get(:frame_types, [])
      # It is said that using this function in a macro is bad,
      # but I can't figure out another way to make it work.
      |> Code.eval_quoted()

    # ^K - VT (Vertical Tab)
    fs_sep = <<0x1C>>
    carriage_return = <<0x0D>>
    mllp_start_of_block = <<0x0B>>
    mllp_end_of_block = fs_sep <> carriage_return

    frame_types =
      opt_frame_types
      |> Enum.concat([
        {mllp_start_of_block, mllp_end_of_block, :mllp}
      ])

    quote do
      @behaviour MLLP.PacketFramer

      require Logger

      @doc false
      @spec handle_packet(packet :: String.t(), state :: MLLP.FramingContext.t()) ::
              {:ok, MLLP.FramingContext.t()}

      unquote do
        frame_types
        |> Enum.map(fn {start_of_block, end_of_block, message_type} ->
          quote do
            def handle_packet(
                  unquote(start_of_block) <> rest_of_packet,
                  %FramingContext{current_message_type: nil} = state
                ) do
              message_type_value = unquote(message_type)

              case String.split(rest_of_packet, unquote(end_of_block), parts: 2) do
                # start but no end found
                [receiver_buffer] ->
                  {:ok,
                   %{
                     state
                     | receiver_buffer: receiver_buffer,
                       current_message_type: message_type_value
                   }}

                # start and end found
                [message, receiver_buffer] ->
                  message_type_atom = get_message_type(message_type_value, message)

                  {:ok, new_state} =
                    state.dispatcher_module.dispatch(message_type_atom, message, %{
                      state
                      | # save leftovers to prepend to next packet
                        receiver_buffer: receiver_buffer,
                        current_message_type: nil
                    })

                  if receiver_buffer == "" do
                    # done with this packet
                    {:ok, new_state}
                  else
                    # the leftovers might have another message to dispatch,
                    # so treat them like a separate packet
                    handle_packet(receiver_buffer, new_state)
                  end
              end
            end

            def handle_packet(
                  unquote(carriage_return),
                  %FramingContext{current_message_type: unquote(message_type)} = state
                ) do

              message_type_value = unquote(message_type)
              check = byte_size(state.receiver_buffer) - 1

              case state.receiver_buffer do
                <<message::binary-size(check), unquote(fs_sep)>> ->
                  message_type_atom = get_message_type(message_type_value, message)

                  {:ok, new_state} =
                    state.dispatcher_module.dispatch(
                      message_type_atom,
                      message,
                      %{
                        state
                        | # save leftovers to prepend to next packet
                          receiver_buffer: "",
                          current_message_type: nil
                      }
                    )

                  {:ok, new_state}

                _ ->
                  {:ok,
                   %{
                     state
                     | receiver_buffer: state.receiver_buffer <> unquote(carriage_return),
                       current_message_type: message_type_value
                   }}
              end
            end

            def handle_packet(
                unquote(mllp_end_of_block),
                  %FramingContext{current_message_type: unquote(message_type)} = state
                ) do

              message_type_value = unquote(message_type) 
              message = state.receiver_buffer
              message_type_atom = get_message_type(message_type_value, message)

              {:ok, new_state} =
                state.dispatcher_module.dispatch(
                  message_type_atom,
                  message,
                  %{
                    state
                    | # save leftovers to prepend to next packet
                      receiver_buffer: "",
                      current_message_type: nil
                  }
                )

              {:ok, new_state}
            end

            def handle_packet(
                  packet,
                  %FramingContext{current_message_type: unquote(message_type)} = state
                ) do
              case String.split(packet, unquote(end_of_block), parts: 2) do
                # no end found
                [new_receiver_buffer] ->
                  {
                    :ok,
                    %{state | receiver_buffer: state.receiver_buffer <> new_receiver_buffer}
                  }

                # end found
                [end_of_message, new_receiver_buffer] ->
                  message = state.receiver_buffer <> end_of_message
                  message_type_value = unquote(message_type)
                  message_type_atom = get_message_type(message_type_value, message)

                  {:ok, new_state} =
                    state.dispatcher_module.dispatch(message_type_atom, message, %{
                      state
                      | # save leftovers to prepend to next packet
                        receiver_buffer: new_receiver_buffer,
                        current_message_type: nil
                    })

                  if new_receiver_buffer == "" do
                    # done with this packet
                    {:ok, new_state}
                  else
                    # the leftovers might have another message to dispatch,
                    # so treat them like a separate packet
                    handle_packet(new_receiver_buffer, new_state)
                  end
              end
            end
          end
        end)
      end

      # TODO: Handle start_of_blocks of other types as well
      def handle_packet(
            unexpected_packet,
            state
          ) do

        to_chunk = unexpected_packet <> state.receiver_buffer

        case String.split(to_chunk, unquote(mllp_start_of_block), parts: 2) do
          [unframed] ->
            handle_unframed(unframed)
            {:ok, %{state | receiver_buffer: ""}}

          [unframed, next_buffer] ->
            handle_unframed(unframed)
            handle_packet(unquote(mllp_start_of_block) <> next_buffer, %{state | receiver_buffer: ""})
        end
      end

      def handle_unframed(unframed) do
        Logger.error("The DefaultPacketFramer is discarding unexpected data: #{unframed}")
      end

      defoverridable handle_unframed: 1

      @doc false
      @spec get_message_type(message_type :: atom(), message :: String.t()) :: atom()
      def get_message_type(:mllp, "MSH" <> _rest_of_message), do: :mllp_hl7

      def get_message_type(:mllp, _message), do: :mllp_unknown
    end
  end
end
