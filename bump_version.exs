#! /usr/bin/env elixir

defmodule Git do
  def latest_tag() do
    "v" <> last_tag = execute(~w[describe --tags --abbrev=0])
    |> String.split("\n")
    |> List.last()

    last_tag
  end

  def branch() do
    execute(~w[rev-parse --abbrev-ref HEAD])
  end

  def sha() do
    ~w[rev-parse HEAD]
    |> execute()
    |> String.slice(0..3)
  end

  defp execute(command) do
    "git"
    |> System.cmd(command)
    |> case do
      {status, 0} -> status
    end
    |> String.trim()
  end
end

defmodule VersionUtility do
  def bump(version, branch) when is_binary(version) do
    version
    |> Version.parse!()
    |> bump(branch)
    |> to_string()
  end

  def bump(version, "main") do
    %{version | patch: version.patch + 1, pre: [], build: nil}
  end

  def bump(%Version{pre: [branch, _]} = version, current_branch) when branch == current_branch do
    %{version | patch: version.patch + 1}
  end

  def bump(version, branch) do
    %{version | patch: version.patch + 1, pre: [scrub_name(branch), 0], build: nil}
  end

  defp scrub_name(branch) do
    branch
    |> (&Regex.replace(~r/[^a-z0-9]+/i, &1, "-")).()
    |> String.downcase()
  end
end

Git.latest_tag()
|> VersionUtility.bump(Git.branch())
|> IO.puts()
