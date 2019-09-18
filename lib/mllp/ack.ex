defmodule MLLP.Ack do
  # # AA – Application Accept
  # # AR - Application Reject
  # # AE – Application Error

  @spec get_ack_for_message(String.t(), atom(), String.t()) :: String.t()

  def get_ack_for_message(message, code, text_message \\ "")

  def get_ack_for_message(message, :application_accept, text_message),
    do: make_ack_hl7(message, "AA", text_message)

  def get_ack_for_message(message, :application_reject, text_message),
    do: make_ack_hl7(message, "AR", text_message)

  def get_ack_for_message(message, :application_error, text_message),
    do: make_ack_hl7(message, "AE", text_message)

  def get_invalid_hl7_received_ack_message() do
    message_control_id = :erlang.unique_integer() |> to_string()

    msh = [
      "MSH",
      "|",
      "^~\\&",
      "????",
      "????",
      "????",
      "????",
      DateTime.utc_now() |> to_string(),
      "",
      "ACK^O01",
      message_control_id,
      "P",
      "2.5"
    ]

    msa = ["MSA", "AR", message_control_id, "Message was not parsable as HL7"]

    HL7.Message.new([msh, msa]) |> to_string()

  end

  defp make_ack_hl7(message, code, text_message) do
    hl7 = message |> HL7.Message.new()
    %HL7.Header{receiving_application: receiving_application, receiving_facility: receiving_facility, sending_application: sending_application, sending_facility: sending_facility, message_control_id: message_control_id} = hl7.header

    msh =
      hl7
      |> HL7.Message.find("MSH")
      |> List.replace_at(4, receiving_facility)
      |> List.replace_at(6, sending_facility)
      |> List.replace_at(3, receiving_application)
      |> List.replace_at(5, sending_application)
      |> List.replace_at(9, "ACK^O01")

    msa = ["MSA", code, message_control_id, text_message]

    HL7.Message.new([msh, msa]) |> to_string()
  end

  def verify_ack_against_message(%HL7.Message{} = message, %HL7.Message{} = ack) do

    message_hl7 = message |> HL7.Message.new()
    message_header = message_hl7.header
    ack_msa = ack |> HL7.Message.new() |> HL7.Message.find("MSA")

    message_control_id = message_header.message_control_id
    ack_message_control_id = ack_msa |> HL7.Segment.get_part(2)
    ack_result = ack_msa |> HL7.Segment.get_part(1)

    if String.contains?(ack_message_control_id, message_control_id) do

      case ack_result do
        "AA" ->
          {:ok, :application_accept}

        "CA" ->
          {:ok, :application_accept}

        "AR" ->
          {:ok, :application_reject}

        "CR" ->
          {:ok, :application_reject}

        "AE" ->
          {:ok, :application_error}

        "CE" ->
          {:ok, :application_error}

        bad_ack_code ->
          {:error,
           %{
             type: :bad_ack_code,
             message: "The value #{bad_ack_code} is not a valid acknowledgment_code"
           }}
      end
    else
      {:error,
       %{
         type: :bad_message_control_id,
         message:
           "The message_control_id of the message-acknowledgement (#{ack_message_control_id}) does not match the message_control_id of message sent (#{
             message_control_id
           })."
       }}
    end
  end

  def verify_ack_against_message(<<"MSH", _::binary>> = message, <<"MSH", _::binary>> = ack) do
    verify_ack_against_message(HL7.Message.new(message), ack)
  end

  def verify_ack_against_message(%HL7.Message{} = message, <<"MSH", _::binary>> = ack) do
    verify_ack_against_message(message, HL7.Message.new(ack))
  end

  def verify_ack_against_message(<<"MSH", _::binary>> = message, %HL7.Message{} = ack) do
    verify_ack_against_message(HL7.Message.new(message), ack)
  end

  def verify_ack_against_message(_message, _ack) do
    {:ok, :application_reject}
  end
end
