defmodule MLLP.LoggerTest do
  use ExUnit.Case, async: true
  alias MLLP.Logger

  import ExUnit.CaptureLog
  @moduletag capture_log: true

  describe "warn/3" do
    test "returns only message" do
      assert capture_log(fn ->
               Logger.warn("message")
             end) =~ "[MLLP] message"
    end

    test "returns message and data with nil reason" do
      assert capture_log(fn ->
               Logger.warn("message", nil, one: "one")
             end) =~ "[MLLP] message - one: one"
    end

    test "don't include commas when only 1 option is provided" do
      assert capture_log(fn ->
               Logger.warn("message", :reason, one: "one")
             end) =~ "[MLLP] message: :reason - one: one"
    end

    test "log message adds comma between data opts" do
      assert capture_log(fn ->
               Logger.warn("message", :reason, one: "one", two: 2, three: :other)
             end) =~
               "[MLLP] message: :reason - one: one, two: 2, three: :other"
    end
  end

  describe "error/3" do
    test "don't include commas when only 1 option is provided" do
      assert capture_log(fn ->
               Logger.error("message", :reason, one: "one")
             end) =~ "[MLLP] message: :reason - one: one"
    end

    test "log message adds comma between data opts" do
      assert capture_log(fn ->
               Logger.error("message", :reason, one: "one", two: 2, three: :other)
             end) =~ "[MLLP] message: :reason - one: one, two: 2, three: :other"
    end
  end
end
