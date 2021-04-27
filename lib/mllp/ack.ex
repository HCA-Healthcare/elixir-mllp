defmodule MLLP.Ack do
  @moduledoc """
  Handles all Ack message operations including getting ack messages for a given HL7 message,
  creating the ack for a given message,
  and handling the return value for different ack codes.
  """

  # # AA – Application Accept
  # # AR - Application Reject
  # # AE – Application Error

  defstruct acknowledgement_code: nil,
            text_message: "",
            hl7_ack_message: nil

  @type t :: %__MODULE__{
          acknowledgement_code: nil | String.t(),
          text_message: String.t(),
          hl7_ack_message: nil | HL7.Message.t()
        }

  @type ack_verification_result ::
          {:ok, atom(), MLLP.Ack.t()}
          | {:error, atom(), MLLP.Ack.t()}
          | {:error, :bad_ack_code, String.t()}
          | {:error, :bad_message_control_id, String.t()}
          | {:error, :invalid_message, String.t()}
          | {:error, :invalid_ack_message, String.t()}

  @spec get_ack_for_message(
          message :: HL7.Message.t() | String.t(),
          acknowledgement_code :: atom() | String.t(),
          text_message :: String.t()
        ) :: HL7.Message.t()

  @type dispatcher_result :: {:ok, :application_accept | :application_error | :application_reject}

  @doc """
  Gets the ack message for a given message and its application status
  """

  def get_ack_for_message(message, code, text_message \\ "")

  def get_ack_for_message(message, :application_accept, text_message),
    do: get_ack_for_message(message, "AA", text_message)

  def get_ack_for_message(message, :application_reject, text_message),
    do: get_ack_for_message(message, "AR", text_message)

  def get_ack_for_message(message, :application_error, text_message),
    do: get_ack_for_message(message, "AE", text_message)

  def get_ack_for_message(message_text, code, text_message) when is_binary(message_text) do
    message_text
    |> HL7.Message.new()
    |> get_ack_for_message(code, text_message)
  end

  def get_ack_for_message(%HL7.Message{} = hl7, code, text_message)
      when code == "AA" or code == "AR" or code == "AE" or
             code == "CA" or code == "CR" or code == "CE" do
    %HL7.Header{
      receiving_application: receiving_application,
      receiving_facility: receiving_facility,
      sending_application: sending_application,
      sending_facility: sending_facility,
      message_control_id: message_control_id
    } = hl7.header

    msh =
      hl7
      |> HL7.Message.find("MSH")
      |> List.replace_at(4, receiving_facility)
      |> List.replace_at(6, sending_facility)
      |> List.replace_at(3, receiving_application)
      |> List.replace_at(5, sending_application)
      |> List.replace_at(9, "ACK^O01")

    msa = ["MSA", code, message_control_id, text_message]

    HL7.Message.raw([msh, msa]) |> HL7.Message.new()
  end

  def get_ack_for_message(%HL7.InvalidMessage{} = invalid_message, _code, _text_message) do
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

    msa = [
      "MSA",
      "AR",
      message_control_id,
      "Message was not parsable as HL7. Reason: #{invalid_message.reason |> to_string()}"
    ]

    HL7.Message.raw([msh, msa]) |> HL7.Message.new()
  end

  @doc """
  Verifies the ack code in the ack message against the original HL7 message. Possible valid codes and their values include:
  AA -- Application Accept
  CA -- Application Accept
  AR -- Application Reject
  CR -- Application Reject
  AE -- Application Error
  CE -- Application Error

  All other possible codes would be considered bad ack codes and the method returns :error
  """

  @spec verify_ack_against_message(
          message :: String.t() | HL7.Message.t(),
          ack_message :: String.t() | HL7.Message.t()
        ) ::
          ack_verification_result()

  def verify_ack_against_message(%HL7.InvalidMessage{} = bad_message, _ack) do
    {:error, :invalid_message, bad_message.reason |> to_string()}
  end

  def verify_ack_against_message(_message, %HL7.InvalidMessage{} = bad_ack) do
    {:error, :invalid_ack_message, bad_ack.reason |> to_string()}
  end

  def verify_ack_against_message(%HL7.Message{} = message, %HL7.Message{} = ack) do
    message_hl7 = message |> HL7.Message.new()
    message_header = message_hl7.header
    ack_msa = ack |> HL7.Message.new() |> HL7.Message.find("MSA")

    message_control_id = message_header.message_control_id
    ack_message_control_id = ack_msa |> HL7.Segment.get_part(2)
    ack_result = ack_msa |> HL7.Segment.get_part(1)
    text_message = ack_msa |> HL7.Segment.get_part(3)

    ack = %__MODULE__{acknowledgement_code: ack_result, text_message: text_message}

    if String.contains?(ack_message_control_id, message_control_id) do
      case ack_result do
        "AA" ->
          {:ok, :application_accept, ack}

        "CA" ->
          {:ok, :application_accept, ack}

        "AR" ->
          {:error, :application_reject, ack}

        "CR" ->
          {:error, :application_reject, ack}

        "AE" ->
          {:error, :application_error, ack}

        "CE" ->
          {:error, :application_error, ack}

        bad_ack_code ->
          {:error, :bad_ack_code, "The value #{bad_ack_code} is not a valid acknowledgment_code"}
      end
    else
      {:error, :bad_message_control_id,
       "The message_control_id of the message #{message_control_id} does not match the message_control_id of the ACK message (#{
         ack_message_control_id
       })."}
    end
  end

  def verify_ack_against_message(message, ack) when is_binary(message) do
    verify_ack_against_message(HL7.Message.new(message), ack)
  end

  def verify_ack_against_message(%HL7.Message{} = message, ack) when is_binary(ack) do
    verify_ack_against_message(message, HL7.Message.new(ack))
  end
end
