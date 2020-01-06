defmodule MLLP.PacketFramerTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  alias MLLP.{DefaultPacketFramer, FramingContext}
  doctest DefaultPacketFramer

  # ^K - VT (Vertical Tab)
  @mllp_start_of_block <<0x0B>>
  @mllp_end_of_block <<0x1C, 0x0D>>

  import Mox

  setup :verify_on_exit!

  describe "DefaultPacketFramer" do
    # Given a block of raw data do we get one or more complete messages?
    # What do we do with leftover?
    # Do we have receiver_buffer from earlier passes that need to be prepended to the beginning?

    test "simple data in MLLP blocks" do
      message = "hello"
      packet = @mllp_start_of_block <> message <> @mllp_end_of_block

      state = %FramingContext{dispatcher_module: MLLP.DispatcherMock}

      MLLP.DispatcherMock
      |> expect(:dispatch, fn :mllp_unknown, ^message, state -> {:ok, state} end)

      {:ok, new_state} = DefaultPacketFramer.handle_packet(packet, state)

      assert state == new_state
    end

    test "half message in MLLP blocks" do
      packet = @mllp_start_of_block <> "message is incomple"
      state = %FramingContext{dispatcher_module: MLLP.DispatcherMock}

      MLLP.DispatcherMock
      |> expect(:dispatch, 0, fn _, _, state -> {:ok, state} end)

      {:ok, new_state} = DefaultPacketFramer.handle_packet(packet, state)
      assert packet == new_state.receiver_buffer
    end

    test "message and a half in MLLP blocks" do
      message = "hello"
      leftover = "More stu"

      packet =
        @mllp_start_of_block <> message <> @mllp_end_of_block <> @mllp_start_of_block <> leftover

      state = %FramingContext{dispatcher_module: MLLP.DispatcherMock}

      MLLP.DispatcherMock
      |> expect(:dispatch, fn :mllp_unknown, ^message, state ->
        {:ok, state}
      end)

      {:ok, new_state} = DefaultPacketFramer.handle_packet(packet, state)

      assert %{state | receiver_buffer: @mllp_start_of_block <> leftover} == new_state
    end

    test "multiple complete messages in MLLP blocks" do
      message1 = "hello"
      message2 = "there"

      packet =
        @mllp_start_of_block <>
          message1 <> @mllp_end_of_block <> @mllp_start_of_block <> message2 <> @mllp_end_of_block

      state = %FramingContext{dispatcher_module: MLLP.DispatcherMock}

      MLLP.DispatcherMock
      |> expect(:dispatch, fn :mllp_unknown, ^message1, state ->
        {:ok, state}
      end)
      |> expect(:dispatch, fn :mllp_unknown, ^message2, state ->
        {:ok, state}
      end)

      {:ok, new_state} = DefaultPacketFramer.handle_packet(packet, state)

      assert state == new_state
    end

    test "multiple messages and a partial message at the end" do
      message1 = "hello"
      message2 = "there"
      partial = "...but wait there is mor"

      packet =
        @mllp_start_of_block <>
          message1 <>
          @mllp_end_of_block <>
          @mllp_start_of_block <>
          message2 <> @mllp_end_of_block <> @mllp_start_of_block <> partial

      state = %FramingContext{dispatcher_module: MLLP.DispatcherMock}

      MLLP.DispatcherMock
      |> expect(:dispatch, fn :mllp_unknown, ^message1, state ->
        {:ok, state}
      end)
      |> expect(:dispatch, fn :mllp_unknown, ^message2, state ->
        {:ok, state}
      end)

      {:ok, new_state} = DefaultPacketFramer.handle_packet(packet, state)

      assert %{state | receiver_buffer: @mllp_start_of_block <> partial} == new_state
    end

    test "simple HL7 message" do
      message = HL7.Examples.wikipedia_sample_hl7()
      packet = @mllp_start_of_block <> message <> @mllp_end_of_block

      state = %FramingContext{dispatcher_module: MLLP.DispatcherMock}

      MLLP.DispatcherMock
      |> expect(:dispatch, fn :mllp_hl7, ^message, state -> {:ok, state} end)

      {:ok, new_state} = DefaultPacketFramer.handle_packet(packet, state)

      assert state == new_state
    end

    test "data outside of a known frame type is discarded" do
      message = "hello"
      packet = message

      state = %FramingContext{dispatcher_module: MLLP.DispatcherMock}

      log =
        capture_log(fn ->
          assert {:ok, new_state} = DefaultPacketFramer.handle_packet(packet, state)
          assert state == new_state
        end)

      assert log =~ "The DefaultPacketFramer is discarding unexpected data: hello"
    end
  end

  describe "Extended PacketFramer" do
    test "data in custom blocks" do
      message = "Como esta"
      packet = "¿" <> message <> "?"

      state = %FramingContext{
        dispatcher_module: MLLP.DispatcherMock
      }

      MLLP.DispatcherMock
      |> expect(:dispatch, fn :spanish_query, ^message, state -> {:ok, state} end)

      {:ok, new_state} = ExtendedFramer.handle_packet(packet, state)

      assert state == new_state
    end

    test "custom block followed by mllp block followed by partial mllp" do
      message1 = "Dónde está el baño"
      message2 = "MSG2"

      packet =
        "¿#{message1}?" <>
          @mllp_start_of_block <>
          message2 <> @mllp_end_of_block <> @mllp_start_of_block <> "Blah blah"

      state = %FramingContext{
        dispatcher_module: MLLP.DispatcherMock
      }

      MLLP.DispatcherMock
      |> expect(:dispatch, fn :spanish_query, ^message1, state -> {:ok, state} end)
      |> expect(:dispatch, fn :mllp_unknown, ^message2, state -> {:ok, state} end)

      {:ok, new_state} = ExtendedFramer.handle_packet(packet, state)

      assert %{state | receiver_buffer: @mllp_start_of_block <> "Blah blah"} == new_state
    end

    test "custom block followed by mllp hl7 block followed by partial mllp" do
      message1 = "Dónde está el baño"
      message2 = HL7.Examples.wikipedia_sample_hl7()

      packet =
        "¿#{message1}?" <>
          @mllp_start_of_block <>
          message2 <> @mllp_end_of_block <> @mllp_start_of_block <> "Blah blah"

      state = %FramingContext{
        dispatcher_module: MLLP.DispatcherMock
      }

      MLLP.DispatcherMock
      |> expect(:dispatch, fn :spanish_query, ^message1, state -> {:ok, state} end)
      |> expect(:dispatch, fn :mllp_hl7, ^message2, state -> {:ok, state} end)

      {:ok, new_state} = ExtendedFramer.handle_packet(packet, state)

      assert %{state | receiver_buffer: @mllp_start_of_block <> "Blah blah"} == new_state
    end
  end
end

defmodule ExtendedFramer do
  use MLLP.PacketFramer, frame_types: [{"¿", "?", :spanish_query}]
end

defmodule FunExtendedFramer do
  use MLLP.PacketFramer, frame_types: [{"<<", ">>", &__MODULE__.message_type/1}]

  def message_type(:message) do
    :fun_message_type
  end
end
