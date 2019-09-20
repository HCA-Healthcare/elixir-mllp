defmodule ReceiverTest do
  use ExUnit.Case
  alias MLLP.Receiver
  doctest Receiver

  import HL7.Query

  def make_msg(body), do: MLLP.Envelope.sb() <> body <> MLLP.Envelope.eb_cr()

  test "Start and stop an MMLP Receiver on a specific port" do
    port = 8129
    {:ok, %{pid: pid}} = MLLP.Receiver.start(port)
    :ok = MLLP.Receiver.stop(port)
    refute Process.alive?(pid)
  end

  test "Receiver returns application_error on junk payload" do
    echo_fun = fn msg -> msg end

    reply = MLLP.Receiver.process_message("JUNK!!!", echo_fun, MLLP.Dispatcher)

    ack_hl7 =
      reply
      |> MLLP.Envelope.unwrap_message()

    code = ack_hl7 |> new() |> get_part("MSA-1")

    assert "AR" == code
  end

  test "Extracting empty buffer returns no message and no remnant" do
    payload = ""
    assert {"", []} == Receiver.extract_messages(payload)
  end

  test "Extracting partial message returns no message and a remnant" do
    payload = "hello!"
    assert {"hello!", []} == Receiver.extract_messages(payload)
  end

  test "Extracting a full message returns one message and no remnant" do
    payload = make_msg("hello!")
    assert {"", ["hello!"]} == Receiver.extract_messages(payload)
  end

  test "Extracting a full message returns one message and a remnant" do
    payload = make_msg("hello!") <> "some more"
    assert {"some more", ["hello!"]} == Receiver.extract_messages(payload)
  end

  test "Extracting two full messages returns two message and no remnant" do
    payload = make_msg("msg1") <> make_msg("msg2")

    assert {"", ["msg1", "msg2"]} == Receiver.extract_messages(payload)
  end

  test "Attempting to extract junk message (missing <SB> and MSH) or will fail." do
    payload = "msg1" <> MLLP.Envelope.eb_cr()

    assert {"", []} == Receiver.extract_messages(payload)
  end

  test "Attempting to extract message with MSH but no <SB> will process and warn." do
    payload = "MSH|blah" <> MLLP.Envelope.eb_cr()

    assert {"", ["MSH|blah"]} == Receiver.extract_messages(payload)
  end

end
