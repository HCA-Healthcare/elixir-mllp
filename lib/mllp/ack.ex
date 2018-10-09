defmodule MLLP.Ack do
  # # AA – Application Accept
  # # AR - Application Reject
  # # AE – Application Error

  require Logger

  @spec get_ack_for_message(String.t(), atom()) :: String.t()

  def get_ack_for_message(message, :application_accept), do: make_ack_hl7(message, "AA")
  def get_ack_for_message(message, :application_reject), do: make_ack_hl7(message, "AR")
  def get_ack_for_message(message, :application_error), do: make_ack_hl7(message, "AE")

  defp make_ack_hl7(message, code) do
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

    msa = ["MSA", code, message_control_id]

    %HL7.Message{hl7 | content: [msh, msa], status: :lists}
    |> HL7.Message.make_raw()
    |> to_string()
  end

  def verify_ack_against_message(message, ack) do
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
end
