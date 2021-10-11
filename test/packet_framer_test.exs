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
      message = "message is incomple"
      packet = @mllp_start_of_block <> message
      state = %FramingContext{dispatcher_module: MLLP.DispatcherMock}

      MLLP.DispatcherMock
      |> expect(:dispatch, 0, fn _, _, state -> {:ok, state} end)

      {:ok, new_state} = DefaultPacketFramer.handle_packet(packet, state)
      assert message == new_state.receiver_buffer
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

      assert %{
               state
               | receiver_buffer: leftover,
                 current_message_type: :mllp
             } == new_state
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

      assert %{
               state
               | receiver_buffer: partial,
                 current_message_type: :mllp
             } == new_state
    end

    test "last byte recieved is the carriage return of an mllp block" do 
      message1 = "hello"

      packet1 = @mllp_start_of_block <> message1 <> <<0x1C>>
      packet2 = <<0x0D>>

      state = %FramingContext{dispatcher_module: MLLP.DispatcherMock}

      expect(MLLP.DispatcherMock, :dispatch, fn :mllp_unknown, ^message1, state ->
        {:ok, state}
      end)

      {:ok, new_state1} = DefaultPacketFramer.handle_packet(packet1, state)
      {:ok, new_state2} = DefaultPacketFramer.handle_packet(packet2, new_state1)
      

      assert %{
               state
               | receiver_buffer: "",
                 current_message_type: nil
      } == new_state2


      message2 = "hello" <> <<0x0D>> <> "world"
      packet3 = @mllp_start_of_block <> message1
      packet4 = <<0x0D>>
      packet5 = "world" <> <<0x1C>>
      packet6 = <<0x0D>>

      expect(MLLP.DispatcherMock, :dispatch, fn :mllp_unknown, ^message2, state ->
        {:ok, state}
      end)

      {:ok, new_state3} = DefaultPacketFramer.handle_packet(packet3, new_state2)
      {:ok, new_state4} = DefaultPacketFramer.handle_packet(packet4, new_state3)
      {:ok, new_state5} = DefaultPacketFramer.handle_packet(packet5, new_state4)
      {:ok, new_state6} = DefaultPacketFramer.handle_packet(packet6, new_state5)

      assert %{
               state
               | receiver_buffer: "",
                 current_message_type: nil
      } == new_state6

    end

    test "last two bytes recieved is the mllp end block" do 
      message1 = "hello"

      packet1 = @mllp_start_of_block <> message1
      packet2 = @mllp_end_of_block

      state = %FramingContext{dispatcher_module: MLLP.DispatcherMock}

      expect(MLLP.DispatcherMock, :dispatch, fn :mllp_unknown, ^message1, state ->
        {:ok, state}
      end)

      {:ok, new_state1} = DefaultPacketFramer.handle_packet(packet1, state)
      {:ok, new_state2} = DefaultPacketFramer.handle_packet(packet2, new_state1)
      

      assert %{
               state
               | receiver_buffer: "",
                 current_message_type: nil
      } == new_state2
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

      assert %{
               state
               | receiver_buffer: "Blah blah",
                 current_message_type: :mllp
             } == new_state
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

      assert %{
               state
               | receiver_buffer: "Blah blah",
                 current_message_type: :mllp
             } == new_state
    end
  end
end

defmodule ExtendedFramer do
  use MLLP.PacketFramer, frame_types: [{"¿", "?", :spanish_query}]

  def get_message_type(:spanish_query, _), do: :spanish_query
end

# TODO: Add test for this:

defmodule FunExtendedFramer do
  use MLLP.PacketFramer, frame_types: [{"<<", ">>", :fun_times}]

  def get_message_type(:fun_times, _message) do
    :fun_message_type
  end
end
