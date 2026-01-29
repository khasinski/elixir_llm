defmodule ElixirLLM.ModelRegistry do
  @moduledoc """
  Centralized model metadata with capabilities, pricing, and context limits.

  ## Usage

      # Get model info
      {:ok, model} = ElixirLLM.ModelRegistry.get("gpt-4o")
      model.context_window  # => 128_000
      model.capabilities    # => [:chat, :streaming, :tools, :vision]

      # Check capabilities
      ElixirLLM.ModelRegistry.supports?("gpt-4o", :vision)  # => true

      # Calculate cost
      ElixirLLM.ModelRegistry.price_for("gpt-4o", 1000, 500)  # => 0.0075

      # List models
      ElixirLLM.ModelRegistry.list(provider: :openai)
      ElixirLLM.ModelRegistry.list(capability: :image_gen)
  """

  alias ElixirLLM.ModelRegistry.Models

  @type capability ::
          :chat
          | :streaming
          | :tools
          | :vision
          | :audio
          | :image_gen
          | :extended_thinking
          | :pdf
          | :embeddings

  @type t :: %__MODULE__{
          id: String.t(),
          provider: atom(),
          display_name: String.t(),
          capabilities: [capability()],
          context_window: pos_integer(),
          max_output_tokens: pos_integer() | nil,
          input_price_per_million: float(),
          output_price_per_million: float(),
          aliases: [String.t()],
          deprecated: boolean(),
          metadata: map()
        }

  defstruct [
    :id,
    :provider,
    :display_name,
    :capabilities,
    :context_window,
    :max_output_tokens,
    :input_price_per_million,
    :output_price_per_million,
    aliases: [],
    deprecated: false,
    metadata: %{}
  ]

  @doc """
  Gets model information by ID or alias.

  ## Examples

      {:ok, model} = ElixirLLM.ModelRegistry.get("gpt-4o")
      {:error, :not_found} = ElixirLLM.ModelRegistry.get("unknown-model")
  """
  @spec get(String.t()) :: {:ok, t()} | {:error, :not_found}
  def get(model_id) do
    model_id_lower = String.downcase(model_id)

    case Enum.find(all_models(), fn model ->
           String.downcase(model.id) == model_id_lower ||
             Enum.any?(model.aliases, &(String.downcase(&1) == model_id_lower))
         end) do
      nil -> {:error, :not_found}
      model -> {:ok, model}
    end
  end

  @doc """
  Lists all models, optionally filtered.

  ## Options

    * `:provider` - Filter by provider atom (e.g., `:openai`, `:anthropic`)
    * `:capability` - Filter by capability (e.g., `:vision`, `:image_gen`)
    * `:deprecated` - Include deprecated models (default: false)

  ## Examples

      ElixirLLM.ModelRegistry.list(provider: :openai)
      ElixirLLM.ModelRegistry.list(capability: :image_gen)
      ElixirLLM.ModelRegistry.list(provider: :anthropic, capability: :extended_thinking)
  """
  @spec list(keyword()) :: [t()]
  def list(filters \\ []) do
    all_models()
    |> filter_by_provider(Keyword.get(filters, :provider))
    |> filter_by_capability(Keyword.get(filters, :capability))
    |> filter_deprecated(Keyword.get(filters, :deprecated, false))
  end

  @doc """
  Checks if a model supports a specific capability.

  ## Examples

      ElixirLLM.ModelRegistry.supports?("gpt-4o", :vision)  # => true
      ElixirLLM.ModelRegistry.supports?("gpt-4o", :image_gen)  # => false
  """
  @spec supports?(String.t(), capability()) :: boolean()
  def supports?(model_id, capability) do
    case get(model_id) do
      {:ok, model} -> capability in model.capabilities
      {:error, _} -> false
    end
  end

  @doc """
  Calculates the cost for a request in USD.

  ## Examples

      # 1000 input tokens, 500 output tokens
      ElixirLLM.ModelRegistry.price_for("gpt-4o", 1000, 500)
      # => 0.0075
  """
  @spec price_for(String.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, float()} | {:error, :not_found}
  def price_for(model_id, input_tokens, output_tokens) do
    case get(model_id) do
      {:ok, model} ->
        input_cost = input_tokens / 1_000_000 * model.input_price_per_million
        output_cost = output_tokens / 1_000_000 * model.output_price_per_million
        {:ok, Float.round(input_cost + output_cost, 6)}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Registers a custom model at runtime.

  Useful for adding models not in the built-in registry.

  ## Examples

      ElixirLLM.ModelRegistry.register(%ElixirLLM.ModelRegistry{
        id: "my-custom-model",
        provider: :openai,
        display_name: "My Custom Model",
        capabilities: [:chat, :streaming],
        context_window: 8192,
        input_price_per_million: 1.0,
        output_price_per_million: 2.0
      })
  """
  @spec register(t()) :: :ok
  def register(%__MODULE__{} = model) do
    existing = Application.get_env(:elixir_llm, :custom_models, [])
    Application.put_env(:elixir_llm, :custom_models, [model | existing])
    :ok
  end

  @doc """
  Returns all registered models (built-in + custom).
  """
  @spec all_models() :: [t()]
  def all_models do
    custom_models = Application.get_env(:elixir_llm, :custom_models, [])
    Models.all() ++ custom_models
  end

  # Private filter functions

  defp filter_by_provider(models, nil), do: models

  defp filter_by_provider(models, provider) do
    Enum.filter(models, &(&1.provider == provider))
  end

  defp filter_by_capability(models, nil), do: models

  defp filter_by_capability(models, capability) do
    Enum.filter(models, &(capability in &1.capabilities))
  end

  defp filter_deprecated(models, true), do: models
  defp filter_deprecated(models, false), do: Enum.reject(models, & &1.deprecated)
end
