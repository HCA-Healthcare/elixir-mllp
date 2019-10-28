defmodule MLLP.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_mllp,
      version: String.trim(File.read!("./VERSION")),
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {MLLP.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ranch, "~> 1.6"},
      {:elixir_hl7, "~> 0.4.0"},
      {:dialyxir, "~> 0.5.1", only: [:dev], runtime: false},
      {:mix_test_watch, "~> 0.9.0", only: :dev, runtime: false},
      {:private, "~> 0.1.1", runtime: false}
    ]
  end
end
