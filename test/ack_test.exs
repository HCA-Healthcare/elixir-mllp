defmodule AckTest do
  use ExUnit.Case
  alias MLLP.Ack
  doctest Ack

  test "The ACK for an HL7 message that was `application_accepted`" do
    hl7_ack = get_ack_for_wikipedia_example(:application_accept)
    assert "AA" == hl7_ack |> HL7.Message.get_value("MSA", 1)
  end

  test "The ACK for an HL7 message that was `application_reject`" do
    hl7_ack = get_ack_for_wikipedia_example(:application_reject)
    assert "AR" == hl7_ack |> HL7.Message.get_value("MSA", 1)
  end

  test "The ACK for an HL7 message that was `application_error`" do
    hl7_ack = get_ack_for_wikipedia_example(:application_error)
    assert "AE" == hl7_ack |> HL7.Message.get_value("MSA", 1)
  end

  test "The ACK for an HL7 message has an MSH with the ACK MessageType" do
    hl7_ack = get_ack_for_wikipedia_example(:application_accept)

    assert "ACK" == hl7_ack.header.message_type
    assert "O01" == hl7_ack.header.trigger_event
  end

  test "The ACK for an HL7 message has an MSA with the original MessageControlID" do
    hl7_ack = get_ack_for_wikipedia_example(:application_accept)

    assert "01052901" == hl7_ack |> HL7.Message.get_value("MSA", 2)
  end

  test "The ACK for an HL7 message has an MSH with the sender and receiver fields reversed" do
    hl7_ack = get_ack_for_wikipedia_example(:application_accept)

    assert "MegaReg" == hl7_ack |> HL7.Message.get_value("MSH", 5)
    assert "XYZHospC" == hl7_ack |> HL7.Message.get_value("MSH", 6)
    assert "SuperOE" == hl7_ack |> HL7.Message.get_value("MSH", 3)
    assert "XYZImgCtr" == hl7_ack |> HL7.Message.get_value("MSH", 4)
  end

  test "The `verify_ack_against_message` accepts good ACK messages" do
    message = HL7.Examples.wikipedia_sample_hl7()
    ack = get_ack_for_wikipedia_example(:application_accept)

    {:ok, :application_accept} = Ack.verify_ack_against_message(message, ack)
  end

  test "The `verify_ack_against_message` errors on ACK containing a bad message_control_id" do
    message = HL7.Examples.wikipedia_sample_hl7()

    bad_ack =
      "MSH|^~\\&|SuperOE|XYZImgCtr|MegaReg|XYZHospC|20060529090131-0500||ACK^O01|01052901|P|2.5\rMSA|AA|**BAD_MESSAGE_CONTROL**\r"

    {:error, %{type: :bad_message_control_id}} = Ack.verify_ack_against_message(message, bad_ack)
  end

  test "The `verify_ack_against_message` errors on ACK with a bad ack_code" do
    message = HL7.Examples.wikipedia_sample_hl7()

    bad_ack =
      "MSH|^~\\&|SuperOE|XYZImgCtr|MegaReg|XYZHospC|20060529090131-0500||ACK^O01|01052901|P|2.5\rMSA|**BAD_ACK_CODE**|01052901\r"

    {:error, %{type: :bad_ack_code}} = Ack.verify_ack_against_message(message, bad_ack)
  end

  defp get_ack_for_wikipedia_example(ack_type) when is_atom(ack_type) do
    incoming_raw = HL7.Examples.wikipedia_sample_hl7()

    incoming_raw
    |> Ack.get_ack_for_message(ack_type)
    |> HL7.Message.new()
  end
end
