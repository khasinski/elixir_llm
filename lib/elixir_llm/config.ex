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

        openrouter: [
          api_key: System.get_env("OPENROUTER_API_KEY")
        ],

        ollama: [
          base_url: "http://localhost:11434"
        ]
  """

  # Provider prefixes for model auto-detection
  # More specific prefixes must be checked first
  # OpenAI models: gpt-4o, gpt-4-turbo, gpt-4.5, o1, o3, chatgpt-4o
  # Anthropic models: claude-sonnet-4, claude-opus-4, claude-3.5-sonnet, claude-3-opus
  # Gemini models: gemini-2.0-flash, gemini-1.5-pro, gemini-1.5-flash
  # Groq models: groq/llama-3.3-70b-versatile
  # Mistral models: mistral-api/mistral-large-latest
  # Together models: together/meta-llama/Llama-3.3-70B-Instruct-Turbo
  @provider_prefixes [
    # Prefixed providers (most specific, check first)
    {"openrouter/", ElixirLLM.Providers.OpenRouter},
    {"groq/", ElixirLLM.Providers.Groq},
    {"together/", ElixirLLM.Providers.Together},
    {"mistral-api/", ElixirLLM.Providers.Mistral},
    # OpenAI models
    {"gpt-", ElixirLLM.Providers.OpenAI},
    {"o1", ElixirLLM.Providers.OpenAI},
    {"o3", ElixirLLM.Providers.OpenAI},
    {"o4", ElixirLLM.Providers.OpenAI},
    {"chatgpt-", ElixirLLM.Providers.OpenAI},
    # Anthropic models
    {"claude-", ElixirLLM.Providers.Anthropic},
    # Gemini models (direct API)
    {"gemini-", ElixirLLM.Providers.Gemini},
    # Mistral models (direct API, without prefix)
    {"mistral-large", ElixirLLM.Providers.Mistral},
    {"mistral-medium", ElixirLLM.Providers.Mistral},
    {"mistral-small", ElixirLLM.Providers.Mistral},
    {"codestral", ElixirLLM.Providers.Mistral},
    {"open-mistral", ElixirLLM.Providers.Mistral},
    {"ministral", ElixirLLM.Providers.Mistral},
    # Ollama models (local)
    {"llama", ElixirLLM.Providers.Ollama},
    {"codellama", ElixirLLM.Providers.Ollama},
    {"phi", ElixirLLM.Providers.Ollama},
    {"gemma", ElixirLLM.Providers.Ollama},
    {"qwen", ElixirLLM.Providers.Ollama},
    {"deepseek", ElixirLLM.Providers.Ollama}
  ]

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

    Enum.find_value(@provider_prefixes, fn {prefix, provider} ->
      if String.starts_with?(model_lower, prefix), do: provider
    end) || ElixirLLM.Providers.OpenAI
  end

  @doc """
  Returns the default provider module.
  """
  @spec default_provider() :: module()
  def default_provider do
    provider_for_model(default_model())
  end
end
