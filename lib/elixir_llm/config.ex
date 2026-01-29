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
    {"xai/", ElixirLLM.Providers.XAI},
    {"deepseek/", ElixirLLM.Providers.DeepSeek},
    {"bedrock/", ElixirLLM.Providers.Bedrock},
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
    # xAI/Grok models (direct)
    {"grok-", ElixirLLM.Providers.XAI},
    # DeepSeek models (direct)
    {"deepseek-", ElixirLLM.Providers.DeepSeek},
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
    {"qwen", ElixirLLM.Providers.Ollama}
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

  # ===========================================================================
  # Configuration Validation
  # ===========================================================================

  @doc """
  Validates that the API key is configured for a provider.

  Returns `{:ok, api_key}` or `{:error, reason}`.
  """
  @spec validate_api_key(atom()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_api_key(provider) do
    case api_key(provider) do
      nil ->
        {:error,
         "API key not configured for #{provider}. Set #{provider_env_var(provider)} or configure in config.exs"}

      "" ->
        {:error, "API key for #{provider} is empty"}

      key when is_binary(key) ->
        {:ok, key}
    end
  end

  @doc """
  Validates API key and raises if not configured.
  """
  @spec validate_api_key!(atom()) :: String.t()
  def validate_api_key!(provider) do
    case validate_api_key(provider) do
      {:ok, key} -> key
      {:error, message} -> raise ArgumentError, message
    end
  end

  @doc """
  Returns the expected environment variable name for a provider's API key.
  """
  @spec provider_env_var(atom()) :: String.t()
  def provider_env_var(:openai), do: "OPENAI_API_KEY"
  def provider_env_var(:anthropic), do: "ANTHROPIC_API_KEY"
  def provider_env_var(:gemini), do: "GOOGLE_API_KEY"
  def provider_env_var(:mistral), do: "MISTRAL_API_KEY"
  def provider_env_var(:groq), do: "GROQ_API_KEY"
  def provider_env_var(:together), do: "TOGETHER_API_KEY"
  def provider_env_var(:openrouter), do: "OPENROUTER_API_KEY"
  def provider_env_var(:xai), do: "XAI_API_KEY"
  def provider_env_var(:deepseek), do: "DEEPSEEK_API_KEY"
  def provider_env_var(:bedrock), do: "AWS_ACCESS_KEY_ID"
  def provider_env_var(provider), do: "#{String.upcase(to_string(provider))}_API_KEY"

  @doc """
  Validates configuration at startup.

  Returns `:ok` or a list of validation errors.
  """
  @spec validate() :: :ok | {:error, [String.t()]}
  def validate do
    errors =
      configured_providers()
      |> Enum.flat_map(&validate_provider/1)

    if errors == [] do
      :ok
    else
      {:error, errors}
    end
  end

  @doc """
  Validates configuration and raises on error.
  """
  @spec validate!() :: :ok
  def validate! do
    case validate() do
      :ok ->
        :ok

      {:error, errors} ->
        raise ArgumentError, "Configuration errors:\n" <> Enum.join(errors, "\n")
    end
  end

  defp configured_providers do
    # Return list of providers that have any configuration
    [:openai, :anthropic, :gemini, :mistral, :groq, :together, :openrouter, :ollama, :xai, :deepseek, :bedrock]
    |> Enum.filter(fn provider ->
      config = provider_config(provider)
      config != [] and Keyword.has_key?(config, :api_key)
    end)
  end

  defp validate_provider(provider) do
    case validate_api_key(provider) do
      {:ok, _} -> []
      {:error, msg} -> [msg]
    end
  end

  @doc """
  Checks if a provider requires an API key.
  """
  @spec requires_api_key?(atom()) :: boolean()
  def requires_api_key?(:ollama), do: false
  def requires_api_key?(_), do: true

  # ===========================================================================
  # Provider Resolution
  # ===========================================================================

  @provider_modules %{
    openai: ElixirLLM.Providers.OpenAI,
    anthropic: ElixirLLM.Providers.Anthropic,
    gemini: ElixirLLM.Providers.Gemini,
    mistral: ElixirLLM.Providers.Mistral,
    groq: ElixirLLM.Providers.Groq,
    together: ElixirLLM.Providers.Together,
    openrouter: ElixirLLM.Providers.OpenRouter,
    ollama: ElixirLLM.Providers.Ollama,
    xai: ElixirLLM.Providers.XAI,
    deepseek: ElixirLLM.Providers.DeepSeek,
    bedrock: ElixirLLM.Providers.Bedrock
  }

  @doc """
  Converts a provider atom or module to the provider module.

  ## Examples

      iex> ElixirLLM.Config.get_provider_module(:openai)
      ElixirLLM.Providers.OpenAI

      iex> ElixirLLM.Config.get_provider_module(ElixirLLM.Providers.Anthropic)
      ElixirLLM.Providers.Anthropic
  """
  @spec get_provider_module(atom() | module()) :: module()
  def get_provider_module(provider) when is_atom(provider) do
    Map.get(@provider_modules, provider) || provider
  end
end
