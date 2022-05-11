defmodule MLLP.LoggerTest do
  use ExUnit.Case, async: true
  alias MLLP.Logger

  import ExUnit.CaptureLog
  @moduletag capture_log: true

  describe "warn/3" do
    test "returns only message" do
      assert capture_log(fn ->
               Logger.warn("message")
             end) =~ "[warning] [MLLP] message\n\e[0m"
    end

    test "returns message and data with nil reason" do
      assert capture_log(fn ->
               Logger.warn("message", nil, one: "one")
             end) =~ "[warning] [MLLP] message - one: \"one\"\n\e[0m"
    end

    test "don't include commas when only 1 option is provided" do
      assert capture_log(fn ->
               Logger.warn("message", :reason, one: "one")
             end) =~ "[warning] [MLLP] message: :reason - one: \"one\"\n\e[0m"
    end

    test "log message adds comma between data opts" do
      assert capture_log(fn ->
               Logger.warn("message", :reason, one: "one", two: 2, three: :other)
             end) =~
               "[warning] [MLLP] message: :reason - one: \"one\", two: 2, three: :other\n\e[0m"
    end
  end

  describe "error/3" do
    test "don't include commas when only 1 option is provided" do
      assert capture_log(fn ->
               Logger.error("message", :reason, one: "one")
             end) =~ "[error] [MLLP] message: :reason - one: \"one\"\n\e[0m"
    end

    test "log message adds comma between data opts" do
      assert capture_log(fn ->
               Logger.error("message", :reason, one: "one", two: 2, three: :other)
             end) =~
               "[error] [MLLP] message: :reason - one: \"one\", two: 2, three: :other\n\e[0m"
    end
  end
end
