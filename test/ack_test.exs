defmodule AckTest do
  use ExUnit.Case
  alias MLLP.Ack
  doctest Ack
  import HL7.Query

  describe "get_ack_for_message" do
    test "for an invalid HL7 message returns a valid AR ack message" do
      bad_message =
        "Bad Message"
        |> HL7.Message.new()

      ack = Ack.get_ack_for_message(bad_message, "AA")
      assert "AR" == ack |> get_part("MSA-1")
      assert "ACK" == ack.header.message_type
      assert ack |> get_part("MSA-3") =~ "missing_header_or_encoding"
    end

    test "for an invalid HL7 string" do
      bad_message = "Bad Message"

      ack = Ack.get_ack_for_message(bad_message, "AA")
      assert "AR" == ack |> get_part("MSA-1")
      assert "ACK" == ack.header.message_type
      assert ack |> get_part("MSA-3") =~ "missing_header_or_encoding"
    end

    test "with code `application_accepted`" do
      hl7_ack = get_ack_for_wikipedia_example(:application_accept)
      assert "AA" == hl7_ack |> get_part("MSA-1")
    end

    test "with code `AA`" do
      hl7_ack = get_ack_for_wikipedia_example("AA")
      assert "AA" == hl7_ack |> get_part("MSA-1")
    end

    test "with code `CA`" do
      hl7_ack = get_ack_for_wikipedia_example("CA")
      assert "CA" == hl7_ack |> get_part("MSA-1")
    end

    test "with code `application_reject`" do
      hl7_ack = get_ack_for_wikipedia_example(:application_reject)
      assert "AR" == hl7_ack |> get_part("MSA-1")
    end

    test "with code `AR`" do
      hl7_ack = get_ack_for_wikipedia_example("AR")
      assert "AR" == hl7_ack |> get_part("MSA-1")
    end

    test "with code `CR`" do
      hl7_ack = get_ack_for_wikipedia_example("CR")
      assert "CR" == hl7_ack |> get_part("MSA-1")
    end

    test "with code `application_error`" do
      hl7_ack = get_ack_for_wikipedia_example(:application_error)
      assert "AE" == hl7_ack |> get_part("MSA-1")
    end

    test "with code `AE`" do
      hl7_ack = get_ack_for_wikipedia_example("AE")
      assert "AE" == hl7_ack |> get_part("MSA-1")
    end

    test "with code `CE`" do
      hl7_ack = get_ack_for_wikipedia_example("CE")
      assert "CE" == hl7_ack |> get_part("MSA-1")
    end

    test "returns an ACK message with the proper message_type" do
      hl7_ack = get_ack_for_wikipedia_example(:application_accept)
      assert "ACK" == hl7_ack.header.message_type
      assert "O01" == hl7_ack.header.trigger_event
    end

    test "return an ACK message with a matching message_control_id" do
      hl7_ack = get_ack_for_wikipedia_example(:application_accept)

      assert "01052901" == hl7_ack |> new() |> get_part("MSA-2")
    end

    test "returns an ACK message with the sender and receiver fields properly reversed" do
      hl7_ack = get_ack_for_wikipedia_example(:application_accept)

      assert "MegaReg" == hl7_ack |> get_part("MSH-5")
      assert "XYZHospC" == hl7_ack |> get_part("MSH-6")
      assert "SuperOE" == hl7_ack |> get_part("MSH-3")
      assert "XYZImgCtr" == hl7_ack |> get_part("MSH-4")
    end
  end

  describe "verify_ack_against_message" do
    test "works fine for a good message and a matching ACK message" do
      message = HL7.Examples.wikipedia_sample_hl7()
      ack_message = get_ack_for_wikipedia_example(:application_accept)

      expected_ack = %Ack{acknowledgement_code: "AA"}

      assert {:ok, :application_accept, expected_ack} ==
               Ack.verify_ack_against_message(message, ack_message)
    end

    test "with code `AA`" do
      hl7_message = HL7.Examples.wikipedia_sample_hl7()
      hl7_ack = get_ack_for_wikipedia_example("AA")
      expected_ack = %Ack{acknowledgement_code: "AA"}

      assert {:ok, :application_accept, expected_ack} ==
               Ack.verify_ack_against_message(hl7_message, hl7_ack)
    end

    test "with code `CA`" do
      hl7_message = HL7.Examples.wikipedia_sample_hl7()
      hl7_ack = get_ack_for_wikipedia_example("CA")
      expected_ack = %Ack{acknowledgement_code: "CA"}

      assert {:ok, :application_accept, expected_ack} ==
               Ack.verify_ack_against_message(hl7_message, hl7_ack)
    end

    test "with code `application_reject`" do
      hl7_message = HL7.Examples.wikipedia_sample_hl7()
      hl7_ack = get_ack_for_wikipedia_example(:application_reject)
      expected_ack = %Ack{acknowledgement_code: "AR"}

      assert {:error, :application_reject, expected_ack} ==
               Ack.verify_ack_against_message(hl7_message, hl7_ack)
    end

    test "with code `AR`" do
      hl7_message = HL7.Examples.wikipedia_sample_hl7()
      hl7_ack = get_ack_for_wikipedia_example("AR")
      expected_ack = %Ack{acknowledgement_code: "AR"}

      assert {:error, :application_reject, expected_ack} ==
               Ack.verify_ack_against_message(hl7_message, hl7_ack)
    end

    test "with code `CR`" do
      hl7_message = HL7.Examples.wikipedia_sample_hl7()
      hl7_ack = get_ack_for_wikipedia_example("CR")
      expected_ack = %Ack{acknowledgement_code: "CR"}

      assert {:error, :application_reject, expected_ack} ==
               Ack.verify_ack_against_message(hl7_message, hl7_ack)
    end

    test "with code `application_error`" do
      hl7_message = HL7.Examples.wikipedia_sample_hl7()
      hl7_ack = get_ack_for_wikipedia_example(:application_error)
      expected_ack = %Ack{acknowledgement_code: "AE"}

      assert {:error, :application_error, expected_ack} ==
               Ack.verify_ack_against_message(hl7_message, hl7_ack)
    end

    test "with code `AE`" do
      hl7_message = HL7.Examples.wikipedia_sample_hl7()
      hl7_ack = get_ack_for_wikipedia_example("AE")
      expected_ack = %Ack{acknowledgement_code: "AE"}

      assert {:error, :application_error, expected_ack} ==
               Ack.verify_ack_against_message(hl7_message, hl7_ack)
    end

    test "with code `CE`" do
      hl7_message = HL7.Examples.wikipedia_sample_hl7()
      hl7_ack = get_ack_for_wikipedia_example("CE")
      expected_ack = %Ack{acknowledgement_code: "CE"}

      assert {:error, :application_error, expected_ack} ==
               Ack.verify_ack_against_message(hl7_message, hl7_ack)
    end

    test "errors on ACK containing a mismatching message_control_id" do
      message = HL7.Examples.wikipedia_sample_hl7()

      bad_ack =
        "MSH|^~\\&|SuperOE|XYZImgCtr|MegaReg|XYZHospC|20060529090131-0500||ACK^O01|01052901|P|2.5\rMSA|AA|**BAD_MESSAGE_CONTROL**\r"

      assert {:error, :bad_message_control_id,
              "The message_control_id of the message 01052901 does not match the message_control_id of the ACK message (**BAD_MESSAGE_CONTROL**)."} ==
               Ack.verify_ack_against_message(message, bad_ack)
    end

    test "errors on ACK with a bad ack_code" do
      message = HL7.Examples.wikipedia_sample_hl7()

      bad_ack =
        "MSH|^~\\&|SuperOE|XYZImgCtr|MegaReg|XYZHospC|20060529090131-0500||ACK^O01|01052901|P|2.5\rMSA|**BAD_ACK_CODE**|01052901\r"

      assert {:error, :bad_ack_code,
              "The value **BAD_ACK_CODE** is not a valid acknowledgment_code"} ==
               Ack.verify_ack_against_message(message, bad_ack)
    end

    test "errors on an invalid message" do
      message = "Nothing like a valid HL7 message"

      ack = ""

      assert {:error, :invalid_message, "missing_header_or_encoding"} ==
               Ack.verify_ack_against_message(message, ack)
    end

    test "errors on an invalid ack message" do
      message = HL7.Examples.wikipedia_sample_hl7()

      bad_ack = "Nothing like a valid ACK message"

      assert {:error, :invalid_ack_message, "missing_header_or_encoding"} ==
               Ack.verify_ack_against_message(message, bad_ack)
    end
  end

  defp get_ack_for_wikipedia_example(ack_type) do
    incoming_raw = HL7.Examples.wikipedia_sample_hl7()

    incoming_raw
    |> Ack.get_ack_for_message(ack_type)
    |> HL7.Message.new()
  end
end
