defmodule EnvelopeTest do
  use ExUnit.Case
  alias MLLP.Envelope
  doctest Envelope

  test "Wrapping a simple message" do
    assert <<11, 121, 101, 115, 28, 13>> == Envelope.wrap_message("yes")
  end

  test "Wrapping an already wrapped message" do
    assert <<11, 121, 101, 115, 28, 13>> == Envelope.wrap_message(<<11, 121, 101, 115, 28, 13>>)
  end

  test "Wrapping an incomplete, partially wrapped message" do
    assert_raise ArgumentError, "MLLP Envelope cannot wrap a partially wrapped message", fn ->
      Envelope.wrap_message(<<11, 121, 101, 115>>)
    end
  end

  test "Unwrapping a simple message" do
    assert "yes" == Envelope.unwrap_message(<<11, 121, 101, 115, 28, 13>>)
  end

  test "Unwrapping an unwrapped message" do
    assert "yes" == Envelope.unwrap_message("yes")
  end

  # test "Unwrapping partially wrapped message (leading wrapper)" do
  #   assert_raise ArgumentError, "MLLP Envelope cannot unwrap a partially wrapped message", fn ->
  #     Envelope.unwrap_message(<<11, 121, 101, 115>>)
  #     |> IO.inspect()
  #   end
  # end

  # test "Unwrapping partially wrapped message (trailing wrapper)" do
  #   assert_raise ArgumentError, "cannot unwrap a partially wrapped message", fn ->
  #     Envelope.unwrap_message(<<101, 115, 28, 13>>)
  #     |> IO.inspect()
  #   end
  # end
end
