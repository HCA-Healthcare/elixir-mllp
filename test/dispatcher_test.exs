defmodule DefaultDispatcherTest do
  use ExUnit.Case
  alias MLLP.DefaultDispatcher
  doctest DefaultDispatcher

  assert "Default dispatcher accepts everything and logs" do
    assert {:ok, :application_accept} == DefaultDispatcher.dispatch("Testing")
  end
end
