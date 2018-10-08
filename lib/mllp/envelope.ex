defmodule MLLP.Envelope do
  @moduledoc """
    Helper functions encoding and decoding MLLP-framed messages.

    Below is an example of an MLLP-framed HL7 payload. Note the <SB>, <CR>, and <EB> characters.

      <SB>
      MSH|^~\\\\&|MegaReg|XYZHospC|SuperOE|XYZImgCtr|20060529090131-0500||ADT^A01^ADT_A01|01052901|P|2.5<CR>
      EVN||200605290901||||200605290900<CR>
      PID|||56782445^^^UAReg^PI||KLEINSAMPLE^BARRY^Q^JR||19620910|M||||||||||0105I30001^^^99DEF^AN<CR>
      PV1||I|W^389^1^UABH^^^^3||||12345^MORGAN^REX^J^^^MD^0010^UAMC^L||6|||||A0<CR>
      OBX|1|NM|^Body Height||1.80|m^Meter^ISO+|||||F<CR>
      OBX|2|NM|^Body Weight||79|kg^Kilogram^ISO+|||||F<CR>
      AL1|1||^ASPIRIN<CR>
      DG1|1||786.50^CHEST PAIN, UNSPECIFIED^I9|||A<CR>
      <EB><CR>

  """
  require Logger

  # ^K - VT (Vertical Tab)
  @sb <<0x0B>>
  # ^\ - FS (File Separator)
  @eb <<0x1C>>
  # ^M - CR (Carriage Return)
  @cr <<0x0D>>
  @ending @eb <> @cr

  @doc """
  The MLLP Start-Block character. In documentation it is often represented as `<SB>`.
  The `sb` is a single-byte character with the ASCII value 0x0B. This character is
  also know as "VT (Vertical Tab)" and may appear as `\\\\v` or `^K` in text editors.

  ## Examples

      iex> MLLP.Envelope.sb
      "\v"

  """
  def sb, do: @sb

  @doc """
  The MLLP End-Block character. In documentation it is often represented as `<EB>`.
  The `eb` is a single-byte character with the ASCII value 0x1C. This character is
  also know as "FS (File Separator)" and may appear as `^\\` in text editors.

  ## Examples

      iex> MLLP.Envelope.eb
      <<28>>

  """
  def eb, do: @eb

  @doc """
  The MLLP Carriage Return character. In documentation it is often represented as `<CR>`.
  The `cr` is a single-byte character with the ASCII value 0x0D. This character
  may appear as "\\\\r" in text editors.

  ## Examples

      iex> MLLP.Envelope.eb
      <<28>>

  """
  def cr, do: @cr

  @doc """
  In MLLP, each message ends with `eb` and `cr`. The `eb_cr` is just a simple concatenation of `eb` and `cr`.

  ## Examples

      iex> MLLP.Envelope.eb_cr
      <<28, 13>>

  """
  def eb_cr, do: @ending

  @doc """
  Wraps a string message in the MLLP start-of-block and end-of-block characters

  Example:
  iex> MLLP.Envelope.wrap_message "hi"
  <<11, 104, 105, 28, 13>>

  """
  def wrap_message(<<11, _::binary>> = message) do
    if String.ends_with?(message, @ending) do
      Logger.debug("MLLP Envelope performed unnecessary wrapping of wrapped message")
      message
    else
      raise(ArgumentError, message: "MLLP Envelope cannot wrap a partially wrapped message")
    end
  end

  def wrap_message(message) when is_binary(message) do
    @sb <> message <> @ending
  end

  @doc """
  Unwraps an MLLP encoded message

  Example:
  iex> MLLP.Envelope.unwrap_message <<11, 104, 105, 28, 13>>
  "hi"

  """
  def unwrap_message(<<11, _::binary>> = wrapped_message) do
    if String.ends_with?(wrapped_message, @ending) do
      unwrap(wrapped_message)
    else
      raise(ArgumentError, message: "MLLP Envelope cannot unwrap a partially wrapped message")
    end
  end

  def unwrap_message(message) when is_binary(message) do
    if String.ends_with?(message, @ending) do
      raise(ArgumentError, message: "cannot unwrap a partially wrapped message")
    else
      Logger.debug("MLLP Envelope performed unnecessary unwrapping of unwrapped message")
      message
    end
  end

  defp unwrap(wrapped) do
    wrapped
    |> String.trim_leading(@sb)
    |> String.trim_trailing(@ending)
  end
end
