defmodule SenderTest do
  use ExUnit.Case, async: false
  alias MLLP.Sender
  doctest Sender

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    attach_telemetry()
    on_exit(fn -> detach_telemetry() end)
  end

  describe "send_hl7_and_receive_ack" do
    test "with valid HL7 returns an AA" do
      address = {127, 0, 0, 1}
      port = 4090
      socket = :socket
      raw_hl7 = HL7.Examples.wikipedia_sample_hl7()
      message = HL7.Message.new(raw_hl7)
      packet = MLLP.Envelope.wrap_message(raw_hl7)

      tcp_reply =
        "MSH|^~\\&|SuperOE|XYZImgCtr|MegaReg|XYZHospC|20060529090131-0500||ACK^O01|01052901|P|2.5\rMSA|AA|01052901|You win!\r"

      MLLP.TCPMock
      |> expect(
        :connect,
        fn ^address, ^port, [:binary, {:packet, 0}, {:active, false}], 2000 ->
          {:ok, socket}
        end
      )
      |> expect(:send, fn ^socket, ^packet -> :ok end)
      |> expect(:recv, fn ^socket, 0 -> {:ok, tcp_reply} end)

      {:ok, sender} = Sender.start_link({address, port}, tcp: MLLP.TCPMock)

      expected_ack = %MLLP.Ack{acknowledgement_code: "AA", text_message: "You win!"}

      assert(
        {:ok, :application_accept, expected_ack} ==
          Sender.send_hl7_and_receive_ack(sender, message)
      )
    end

    test "send_hl7_and_receive_ack given a string" do
      address = {127, 0, 0, 1}
      port = 4090
      socket = :socket
      message = "Sore disappointment"

      MLLP.TCPMock
      |> expect(
        :connect,
        fn ^address, ^port, [:binary, {:packet, 0}, {:active, false}], 2000 ->
          {:ok, socket}
        end
      )

      {:ok, sender} = Sender.start_link({address, port}, tcp: MLLP.TCPMock)

      assert_raise(FunctionClauseError, fn ->
        Sender.send_hl7_and_receive_ack(sender, message)
      end)
    end
  end

  describe "send_hl7" do
    test "as a message" do
      address = {127, 0, 0, 1}
      port = 4090
      socket = :socket

      raw_hl7 = HL7.Examples.wikipedia_sample_hl7()

      message =
        raw_hl7
        |> HL7.Message.new()

      packet = MLLP.Envelope.wrap_message(raw_hl7)

      MLLP.TCPMock
      |> expect(
        :connect,
        fn ^address, ^port, [:binary, {:packet, 0}, {:active, false}], 2000 ->
          {:ok, socket}
        end
      )
      |> expect(:send, fn ^socket, ^packet -> :ok end)

      {:ok, sender} = Sender.start_link({address, port}, tcp: MLLP.TCPMock)

      assert({:ok, :sent} == Sender.send_hl7(sender, message))
    end

    test "send_hl7 with a non-hl7 string" do
      address = {127, 0, 0, 1}
      port = 4090
      socket = :socket
      message = "I am not HL7"

      MLLP.TCPMock
      |> expect(
        :connect,
        fn ^address, ^port, [:binary, {:packet, 0}, {:active, false}], 2000 ->
          {:ok, socket}
        end
      )

      {:ok, sender} = Sender.start_link({address, port}, tcp: MLLP.TCPMock)

      assert_raise(FunctionClauseError, fn ->
        Sender.send_hl7(sender, message)
      end)
    end

    test "Sending HL7 and receiving an application reject" do
    end

    test "Sending HL7 and receiving an application error" do
    end
  end

  describe "Sending non-HL7" do
    # expect_reply: true/false
    # wrap_message: true
    # reply_timout: ?
  end

  describe "Sending raw" do
    # expect_reply: true/false
    # wrap_message: false
    # reply_timout: ?
  end

  test "send_non_hl7_and_receive_reply" do
    address = {127, 0, 0, 1}
    port = 4090

    socket = :socket
    message = "Hello, it's me"
    packet = MLLP.Envelope.wrap_message(message)
    reply = "Good reply"

    MLLP.TCPMock
    |> expect(
      :connect,
      fn ^address, ^port, [:binary, {:packet, 0}, {:active, false}], 2000 ->
        {:ok, socket}
      end
    )
    |> expect(:send, fn ^socket, ^packet -> :ok end)
    |> expect(:recv, fn ^socket, 0, _ -> {:ok, reply} end)

    {:ok, sender} = Sender.start_link({address, port}, tcp: MLLP.TCPMock)

    assert({:ok, reply} == Sender.send_non_hl7_and_receive_reply(sender, message))
  end

  test "send_non_hl7" do
    address = {127, 0, 0, 1}
    port = 4090

    socket = :socket
    message = "Hello, it's me"
    packet = MLLP.Envelope.wrap_message(message)

    MLLP.TCPMock
    |> expect(
      :connect,
      fn ^address, ^port, [:binary, {:packet, 0}, {:active, false}], 2000 ->
        {:ok, socket}
      end
    )
    |> expect(:send, fn ^socket, ^packet -> :ok end)

    {:ok, sender} = Sender.start_link({address, port}, tcp: MLLP.TCPMock)

    assert({:ok, :sent} == Sender.send_non_hl7(sender, message))
  end

  test "send_non_hl7_and_receive_reply that looks like HL7" do
    address = {127, 0, 0, 1}
    port = 4090

    socket = :socket
    message = "MSH1234"
    packet = MLLP.Envelope.wrap_message(message)
    reply = "Good reply"

    MLLP.TCPMock
    |> expect(
      :connect,
      fn ^address, ^port, [:binary, {:packet, 0}, {:active, false}], 2000 ->
        {:ok, socket}
      end
    )
    |> expect(:send, fn ^socket, ^packet -> :ok end)
    |> expect(:recv, fn ^socket, 0, _ -> {:ok, reply} end)

    {:ok, sender} = Sender.start_link({address, port}, tcp: MLLP.TCPMock)

    assert({:ok, reply} == Sender.send_non_hl7_and_receive_reply(sender, message))
  end

  test "send_raw_and_receive_reply" do
    address = {127, 0, 0, 1}
    port = 4090

    socket = :socket
    message = "ABCDEFG"
    reply = "Good reply"

    MLLP.TCPMock
    |> expect(
      :connect,
      fn ^address, ^port, [:binary, {:packet, 0}, {:active, false}], 2000 ->
        {:ok, socket}
      end
    )
    |> expect(:send, fn ^socket, ^message -> :ok end)
    |> expect(:recv, fn ^socket, 0, _ -> {:ok, reply} end)

    {:ok, sender} = Sender.start_link({address, port}, tcp: MLLP.TCPMock)

    assert({:ok, reply} == Sender.send_raw_and_receive_reply(sender, message))
  end

  test "send_raw" do
    address = {127, 0, 0, 1}
    port = 4090

    socket = :socket
    message = "ABCDEFG"

    MLLP.TCPMock
    |> expect(
      :connect,
      fn ^address, ^port, [:binary, {:packet, 0}, {:active, false}], 2000 ->
        {:ok, socket}
      end
    )
    |> expect(:send, fn ^socket, ^message -> :ok end)

    {:ok, sender} = Sender.start_link({address, port}, tcp: MLLP.TCPMock)

    assert({:ok, :sent} == Sender.send_raw(sender, message))
  end

  defp telemetry_event(
         [:mllp, :sender, event_name] = _full_event_name,
         measurements,
         metadata,
         config
       ) do
    send(
      config.test_pid,
      {:telemetry_call, %{event_name: event_name, measurements: measurements, metadata: metadata}}
    )
  end

  defp attach_telemetry() do
    event_names =
      [:status, :sending, :received]
      |> Enum.map(fn e -> [:mllp, :sender, e] end)

    :telemetry.attach_many("telemetry_events", event_names, &telemetry_event/4, %{
      test_pid: self()
    })
  end

  defp detach_telemetry() do
    :telemetry.detach("telemetry_events")
  end
end
