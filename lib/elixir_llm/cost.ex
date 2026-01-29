defmodule ElixirLLM.Cost do
  @moduledoc """
  Per-request cost calculation based on token usage.

  Calculates costs in USD using pricing data from the Model Registry.

  ## Examples

      # Calculate from a response
      {:ok, response} = ElixirLLM.chat("Hello!")
      cost = ElixirLLM.Cost.calculate(response)
      IO.puts("Cost: $" <> to_string(cost.total))

      # Calculate from tokens directly
      cost = ElixirLLM.Cost.calculate("gpt-4o", 1000, 500)
      # => %{input: 0.0025, output: 0.005, total: 0.0075, currency: "USD"}

      # Estimate before making a request
      estimate = ElixirLLM.Cost.estimate("gpt-4o", 1000)
      IO.puts("Estimated cost: $" <> to_string(estimate.total))

      # Track costs via telemetry
      :telemetry.attach("cost-tracker", [:elixir_llm, :chat, :stop], fn _, measurements, metadata, _ ->
        cost = ElixirLLM.Cost.calculate(metadata.model, measurements.input_tokens, measurements.output_tokens)
        Logger.info("Request cost: $" <> to_string(cost.total))
      end, nil)

  ## Pricing Data

  Pricing is retrieved from the Model Registry. If a model is not found,
  a zero cost is returned. You can register custom models with pricing:

      ElixirLLM.ModelRegistry.register(%ElixirLLM.ModelRegistry{
        id: "my-custom-model",
        provider: :custom,
        display_name: "My Model",
        capabilities: [:chat],
        context_window: 8192,
        input_price_per_million: 1.00,
        output_price_per_million: 2.00
      })
  """

  alias ElixirLLM.{ModelRegistry, Response}

  @type t :: %{
          input: float(),
          output: float(),
          total: float(),
          currency: String.t()
        }

  @doc """
  Calculates cost from a Response struct.

  ## Examples

      {:ok, response} = ElixirLLM.chat("Hello!")
      cost = ElixirLLM.Cost.calculate(response)
      cost.total  # => 0.000045
  """
  @spec calculate(Response.t()) :: t()
  def calculate(%Response{model: model, input_tokens: input, output_tokens: output}) do
    calculate(model, input || 0, output || 0)
  end

  @doc """
  Calculates cost from model ID and token counts.

  ## Examples

      cost = ElixirLLM.Cost.calculate("gpt-4o", 1000, 500)
      cost.total  # => 0.0075
  """
  @spec calculate(String.t(), non_neg_integer(), non_neg_integer()) :: t()
  def calculate(model, input_tokens, output_tokens) when is_binary(model) do
    case ModelRegistry.get(model) do
      {:ok, model_info} ->
        input_cost = input_tokens / 1_000_000 * model_info.input_price_per_million
        output_cost = output_tokens / 1_000_000 * model_info.output_price_per_million

        %{
          input: Float.round(input_cost, 6),
          output: Float.round(output_cost, 6),
          total: Float.round(input_cost + output_cost, 6),
          currency: "USD"
        }

      {:error, :not_found} ->
        # Model not in registry, return zero cost
        %{
          input: 0.0,
          output: 0.0,
          total: 0.0,
          currency: "USD"
        }
    end
  end

  @doc """
  Estimates cost before making a request.

  Uses the input token count and estimates output as 2x input
  (a conservative estimate for typical conversations).

  ## Options

    * `:estimated_output_tokens` - Override the output token estimate

  ## Examples

      estimate = ElixirLLM.Cost.estimate("gpt-4o", 1000)
      IO.puts("Estimated cost: $" <> to_string(estimate.total))

      # With custom output estimate
      estimate = ElixirLLM.Cost.estimate("gpt-4o", 1000, estimated_output_tokens: 500)
  """
  @spec estimate(String.t(), non_neg_integer(), keyword()) :: t()
  def estimate(model, input_tokens, opts \\ []) do
    output_tokens = Keyword.get(opts, :estimated_output_tokens, input_tokens * 2)
    calculate(model, input_tokens, output_tokens)
  end

  @doc """
  Calculates the cost per token for a model.

  Returns pricing per single token (not per million).

  ## Examples

      pricing = ElixirLLM.Cost.per_token_pricing("gpt-4o")
      # => {:ok, %{input: 0.0000025, output: 0.00001}}
  """
  @spec per_token_pricing(String.t()) :: {:ok, %{input: float(), output: float()}} | {:error, :not_found}
  def per_token_pricing(model) do
    case ModelRegistry.get(model) do
      {:ok, model_info} ->
        {:ok,
         %{
           input: model_info.input_price_per_million / 1_000_000,
           output: model_info.output_price_per_million / 1_000_000
         }}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Formats a cost as a human-readable string.

  ## Examples

      cost = ElixirLLM.Cost.calculate("gpt-4o", 1000, 500)
      ElixirLLM.Cost.format(cost)
      # => "$0.0075"

      ElixirLLM.Cost.format(cost, precision: 4)
      # => "$0.0075"
  """
  @spec format(t(), keyword()) :: String.t()
  def format(%{total: total, currency: "USD"}, opts \\ []) do
    precision = Keyword.get(opts, :precision, 6)
    "$#{:erlang.float_to_binary(total, decimals: precision)}"
  end

  @doc """
  Accumulates costs from multiple responses.

  ## Examples

      costs = [cost1, cost2, cost3]
      total = ElixirLLM.Cost.sum(costs)
      total.total  # => sum of all costs
  """
  @spec sum([t()]) :: t()
  def sum(costs) when is_list(costs) do
    Enum.reduce(costs, zero(), fn cost, acc ->
      %{
        input: acc.input + cost.input,
        output: acc.output + cost.output,
        total: acc.total + cost.total,
        currency: "USD"
      }
    end)
  end

  @doc """
  Returns a zero cost structure.
  """
  @spec zero() :: t()
  def zero do
    %{
      input: 0.0,
      output: 0.0,
      total: 0.0,
      currency: "USD"
    }
  end
end
