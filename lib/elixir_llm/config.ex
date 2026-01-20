defmodule ElixirLLM.Config do
  @moduledoc """
  Configuration management for ElixirLLM.

  ## Configuration

  Configure ElixirLLM in your `config/config.exs`:

      config :elixir_llm,
        default_model: "gpt-4o",

        openai: [
          api_key: System.get_env("OPENAI_API_KEY"),
          base_url: "https://api.openai.com/v1"
        ],

        anthropic: [
          api_key: System.get_env("ANTHROPIC_API_KEY"),
          base_url: "https://api.anthropic.com"
        ],

        ollama: [
          base_url: "http://localhost:11434"
        ]
  """

  @provider_prefixes %{
    "gpt-" => ElixirLLM.Providers.OpenAI,
    "o1-" => ElixirLLM.Providers.OpenAI,
    "o3-" => ElixirLLM.Providers.OpenAI,
    "chatgpt-" => ElixirLLM.Providers.OpenAI,
    "claude-" => ElixirLLM.Providers.Anthropic,
    "llama" => ElixirLLM.Providers.Ollama,
    "mistral" => ElixirLLM.Providers.Ollama,
    "codellama" => ElixirLLM.Providers.Ollama,
    "phi" => ElixirLLM.Providers.Ollama,
    "gemma" => ElixirLLM.Providers.Ollama,
    "qwen" => ElixirLLM.Providers.Ollama,
    "deepseek" => ElixirLLM.Providers.Ollama
  }

  @doc """
  Returns the default model.
  """
  @spec default_model() :: String.t()
  def default_model do
    Application.get_env(:elixir_llm, :default_model, "gpt-4o")
  end

  @doc """
  Returns configuration for a specific provider.
  """
  @spec provider_config(atom()) :: keyword()
  def provider_config(provider) do
    Application.get_env(:elixir_llm, provider, [])
  end

  @doc """
  Returns the API key for a provider.
  """
  @spec api_key(atom()) :: String.t() | nil
  def api_key(provider) do
    provider
    |> provider_config()
    |> Keyword.get(:api_key)
  end

  @doc """
  Returns the base URL for a provider.
  """
  @spec base_url(atom()) :: String.t() | nil
  def base_url(provider) do
    provider
    |> provider_config()
    |> Keyword.get(:base_url)
  end

  @doc """
  Determines the provider module for a given model ID.
  """
  @spec provider_for_model(String.t()) :: module()
  def provider_for_model(model_id) do
    model_lower = String.downcase(model_id)

    Enum.find_value(@provider_prefixes, ElixirLLM.Providers.OpenAI, fn {prefix, provider} ->
      if String.starts_with?(model_lower, prefix), do: provider
    end)
  end

  @doc """
  Returns the default provider module.
  """
  @spec default_provider() :: module()
  def default_provider do
    provider_for_model(default_model())
  end
end
