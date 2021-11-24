defmodule MLLP.Client.Error do
  defexception [:context, :reason, :message]

  @type t :: %MLLP.Client.Error{}
end
