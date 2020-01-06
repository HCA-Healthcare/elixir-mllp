defmodule MLLP.DefaultPacketFramer do
  require Logger

  use MLLP.PacketFramer

  def handle_packet(
        unexpected_packet,
        state
      ) do
    mllp_start_of_block = <<0x0B>>

    to_chunk = unexpected_packet <> state.receiver_buffer

    case String.split(to_chunk, mllp_start_of_block, parts: 2) do
      [throw_away] ->
        Logger.error("The DefaultPacketFramer is discarding unexpected data: #{throw_away}")

        {:ok, %{state | receiver_buffer: ""}}

      [throw_away, next_buffer] ->
        Logger.error("The DefaultPacketFramer is discarding unexpected data: #{throw_away}")

        handle_packet(mllp_start_of_block <> next_buffer, %{state | receiver_buffer: ""})
    end
  end
end
