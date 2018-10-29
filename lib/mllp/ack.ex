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

    %HL7.Message{
      separators: %HL7.Separators{},
      content: [
        msh,
        msa
      ],
      status: :lists
    }
    |> to_string()
  end

  defp make_ack_hl7(message, code, text_message) do
    hl7 = message |> HL7.Message.new() |> HL7.Message.make_lists()

    sending_facility = hl7 |> HL7.Message.get_value("MSH", 4)
    sending_app = hl7 |> HL7.Message.get_value("MSH", 3)
    receiving_facility = hl7 |> HL7.Message.get_value("MSH", 6)
    receiving_app = hl7 |> HL7.Message.get_value("MSH", 5)
    message_control_id = hl7 |> HL7.Message.get_value("MSH", 10)

    msh =
      hl7
      |> HL7.Message.get_segment("MSH")
      |> List.replace_at(4, receiving_facility)
      |> List.replace_at(6, sending_facility)
      |> List.replace_at(3, receiving_app)
      |> List.replace_at(5, sending_app)
      |> List.replace_at(9, "ACK^O01")

    msa = ["MSA", code, message_control_id, text_message]

    result =
      %HL7.Message{hl7 | content: [msh, msa], status: :lists}
      |> HL7.Message.make_raw()
      |> to_string()

    result
  end

  def verify_ack_against_message(%HL7.Message{} = message, %HL7.Message{} = ack) do
    message_hl7 = message |> HL7.Message.make_lists()
    ack_hl7 = ack |> HL7.Message.make_lists()

    message_control_id = message_hl7 |> HL7.Message.get_value("MSH", 10)
    ack_message_control_id = ack_hl7 |> HL7.Message.get_value("MSA", 2)

    # todo make strict matching options
    if String.contains?(ack_message_control_id, message_control_id) do
      ack_hl7
      |> HL7.Message.get_value("MSA", 1)
      |> case do
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
