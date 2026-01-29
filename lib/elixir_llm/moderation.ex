defmodule ElixirLLM.Moderation do
  @moduledoc """
  Content moderation using OpenAI's moderation API.

  Checks text for content that violates OpenAI's usage policies.

  ## Examples

      # Check single text
      {:ok, result} = ElixirLLM.Moderation.moderate("Some text to check")

      if result.flagged do
        IO.puts("Flagged for: " <> Enum.join(result.flagged_categories, ", "))
      end

      # Check multiple texts
      {:ok, results} = ElixirLLM.Moderation.moderate(["text 1", "text 2"])

      # Quick check
      if ElixirLLM.Moderation.flagged?("suspicious text") do
        IO.puts("Content was flagged!")
      end

  ## Categories

  The moderation API checks for the following categories:

    * `:sexual` - Sexual content
    * `:hate` - Hate speech
    * `:harassment` - Harassment
    * `:self_harm` - Self-harm content
    * `:violence` - Violence
    * `:sexual_minors` - Sexual content involving minors
    * `:hate_threatening` - Threatening hate speech
    * `:violence_graphic` - Graphic violence
    * `:self_harm_intent` - Self-harm intent
    * `:self_harm_instructions` - Self-harm instructions
    * `:harassment_threatening` - Threatening harassment
  """

  alias ElixirLLM.{Config, Telemetry}
  alias ElixirLLM.Error.Helpers, as: ErrorHelpers
  alias ElixirLLM.Providers.Base

  @type category ::
          :sexual
          | :hate
          | :harassment
          | :self_harm
          | :violence
          | :sexual_minors
          | :hate_threatening
          | :violence_graphic
          | :self_harm_intent
          | :self_harm_instructions
          | :harassment_threatening

  @type t :: %__MODULE__{
          flagged: boolean(),
          categories: %{category() => boolean()},
          category_scores: %{category() => float()},
          flagged_categories: [category()]
        }

  defstruct [:flagged, :categories, :category_scores, :flagged_categories]

  @doc """
  Moderates text content for policy violations.

  ## Options

    * `:model` - Model to use (default: "omni-moderation-latest")

  ## Returns

    * `{:ok, result}` - Single result when input is a string
    * `{:ok, [results]}` - List of results when input is a list
    * `{:error, reason}` - On failure

  ## Examples

      {:ok, result} = ElixirLLM.Moderation.moderate("Hello world")
      result.flagged  # => false

      {:ok, results} = ElixirLLM.Moderation.moderate(["text1", "text2"])
      Enum.any?(results, & &1.flagged)
  """
  @spec moderate(String.t() | [String.t()], keyword()) ::
          {:ok, t() | [t()]} | {:error, term()}
  def moderate(input, opts \\ []) do
    model = Keyword.get(opts, :model, "omni-moderation-latest")
    metadata = %{model: model}

    Telemetry.span(:moderation, metadata, fn ->
      moderate_openai(input, model)
    end)
  end

  @doc """
  Quick check if content is flagged.

  Returns `true` if the content violates any policy, `false` otherwise.
  Returns `false` on API errors (fail-open behavior).

  ## Examples

      if ElixirLLM.Moderation.flagged?("some text") do
        IO.puts("Content was flagged!")
      end
  """
  @spec flagged?(String.t(), keyword()) :: boolean()
  def flagged?(text, opts \\ []) do
    case moderate(text, opts) do
      {:ok, result} -> result.flagged
      {:error, _} -> false
    end
  end

  @doc """
  Returns the highest-scoring category for flagged content.

  Returns `nil` if content is not flagged or on error.

  ## Examples

      {:ok, category} = ElixirLLM.Moderation.top_category("some text")
      # => {:ok, :harassment} or {:ok, nil}
  """
  @spec top_category(String.t(), keyword()) :: {:ok, category() | nil} | {:error, term()}
  def top_category(text, opts \\ []) do
    case moderate(text, opts) do
      {:ok, result} ->
        {:ok, extract_top_category(result)}

      {:error, _} = error ->
        error
    end
  end

  defp extract_top_category(%{flagged: false}), do: nil

  defp extract_top_category(%{flagged: true, category_scores: scores}) do
    {category, _score} = Enum.max_by(scores, fn {_k, v} -> v end)
    category
  end

  # ===========================================================================
  # OpenAI Implementation
  # ===========================================================================

  defp moderate_openai(input, model) do
    base_url = Config.base_url(:openai) || "https://api.openai.com/v1"
    api_key = Config.api_key(:openai)
    timeout = Base.get_timeout(:openai)

    body = %{
      model: model,
      input: input
    }

    case Req.post(
           base_url <> "/moderations",
           json: body,
           headers: Base.bearer_headers(api_key),
           receive_timeout: timeout
         ) do
      {:ok, %{status: 200, body: response}} ->
        results = parse_moderation_results(response)

        if is_list(input) do
          {:ok, results}
        else
          {:ok, hd(results)}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, Base.parse_error(status, body, :openai)}

      {:error, reason} ->
        {:error, ErrorHelpers.from_transport_error(reason, :openai)}
    end
  end

  defp parse_moderation_results(response) do
    Enum.map(response["results"] || [], fn result ->
      categories = parse_categories(result["categories"] || %{})

      flagged_cats =
        categories
        |> Enum.filter(fn {_, v} -> v end)
        |> Enum.map(&elem(&1, 0))

      %__MODULE__{
        flagged: result["flagged"] || false,
        categories: categories,
        category_scores: parse_category_scores(result["category_scores"] || %{}),
        flagged_categories: flagged_cats
      }
    end)
  end

  @category_keys %{
    "sexual" => :sexual,
    "hate" => :hate,
    "harassment" => :harassment,
    "self-harm" => :self_harm,
    "violence" => :violence,
    "sexual/minors" => :sexual_minors,
    "hate/threatening" => :hate_threatening,
    "violence/graphic" => :violence_graphic,
    "self-harm/intent" => :self_harm_intent,
    "self-harm/instructions" => :self_harm_instructions,
    "harassment/threatening" => :harassment_threatening
  }

  defp parse_categories(cats) do
    Map.new(@category_keys, fn {api_key, atom_key} ->
      {atom_key, cats[api_key] || false}
    end)
  end

  defp parse_category_scores(scores) do
    Map.new(@category_keys, fn {api_key, atom_key} ->
      {atom_key, scores[api_key] || 0.0}
    end)
  end
end
