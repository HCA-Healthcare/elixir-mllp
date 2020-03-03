defmodule MLLP.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_mllp,
      version: String.trim(File.read!("./VERSION")),
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      test_coverage: [tool: ExCoveralls]
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
      {:telemetry, "~> 0.4.1"},
      {:ranch, "~> 1.7.1"},
      {:elixir_hl7, "~> 0.6.0"},
      {:dialyxir, "~> 0.5.1", only: [:dev], runtime: false},
      {:mix_test_watch, "~> 0.9.0", only: :dev, runtime: false},
      {:mox, "~> 0.5", only: :test},
      {:excoveralls, "~> 0.12.0", only: :test, runtime: false},
      {:private, "~> 0.1.1", runtime: false}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
