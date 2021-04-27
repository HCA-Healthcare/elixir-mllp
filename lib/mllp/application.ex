defmodule MLLP.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @spec start(any, any) :: {:error, any} | {:ok, pid}
  def start(_type, _args) do
    # List all child processes to be supervised
    children = []

    opts = [strategy: :one_for_one, name: MLLP.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
