defmodule ElixirLLM.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/khasinski/elixir_llm"

  def project do
    [
      app: :elixir_llm,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: dialyzer(),
      name: "ElixirLLM",
      source_url: @source_url
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ElixirLLM.Application, []}
    ]
  end

  defp deps do
    [
      # HTTP client
      {:req, "~> 0.5"},

      # JSON encoding/decoding
      {:jason, "~> 1.4"},

      # Observability
      {:telemetry, "~> 1.2"},

      # Option validation
      {:nimble_options, "~> 1.1"},

      # Development and testing
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp description do
    """
    A unified Elixir API for LLMs. One beautiful interface for OpenAI, Anthropic, Ollama, and more.
    Inspired by RubyLLM.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      maintainers: ["Chris Hasiński"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      source_ref: "v#{@version}"
    ]
  end
end
