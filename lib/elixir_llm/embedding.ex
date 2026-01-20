defmodule ElixirLLM.Embedding do
  @moduledoc """
  Generate embeddings (vector representations) of text.

  Embeddings are useful for:
  - Semantic search
  - Text similarity
  - Clustering
  - RAG (Retrieval Augmented Generation)

  ## Example

      # Single text
      {:ok, embedding} = ElixirLLM.embed("Hello, world!")
      embedding.vector  # => [0.123, -0.456, ...]

      # Multiple texts (batched)
      {:ok, embeddings} = ElixirLLM.embed(["Hello", "World"])

      # With specific model
      {:ok, embedding} = ElixirLLM.embed("Hello", model: "text-embedding-3-large")
  """

  alias ElixirLLM.{Config, Telemetry}

  @type t :: %__MODULE__{
          vector: [float()],
          model: String.t(),
          input_tokens: non_neg_integer() | nil
        }

  defstruct [:vector, :model, :input_tokens]

  @doc """
  Generates embeddings for the given text(s).

  ## Options

    * `:model` - The embedding model to use (default: "text-embedding-3-small")
    * `:dimensions` - Number of dimensions (for models that support it)

  ## Examples

      {:ok, embedding} = ElixirLLM.Embedding.create("Hello, world!")
      {:ok, embeddings} = ElixirLLM.Embedding.create(["Hello", "World"])
  """
  @spec create(String.t() | [String.t()], keyword()) ::
          {:ok, t() | [t()]} | {:error, term()}
  def create(input, opts \\ [])

  def create(text, opts) when is_binary(text) do
    case create([text], opts) do
      {:ok, [embedding]} -> {:ok, embedding}
      {:error, reason} -> {:error, reason}
    end
  end

  def create(texts, opts) when is_list(texts) do
    model = Keyword.get(opts, :model, "text-embedding-3-small")
    dimensions = Keyword.get(opts, :dimensions)

    metadata = %{model: model, count: length(texts)}

    Telemetry.span(:embed, metadata, fn ->
      body =
        %{
          model: model,
          input: texts
        }
        |> maybe_add(:dimensions, dimensions)

      case make_request(body) do
        {:ok, %{status: 200, body: response_body}} ->
          embeddings = parse_response(response_body, model)
          {:ok, embeddings}

        {:ok, %{status: status, body: body}} ->
          {:error, parse_error(status, body)}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  @doc """
  Calculates cosine similarity between two embeddings.

  Returns a value between -1 and 1, where 1 means identical.
  """
  @spec cosine_similarity(t() | [float()], t() | [float()]) :: float()
  def cosine_similarity(%__MODULE__{vector: v1}, %__MODULE__{vector: v2}) do
    cosine_similarity(v1, v2)
  end

  def cosine_similarity(v1, v2) when is_list(v1) and is_list(v2) do
    dot = Enum.zip(v1, v2) |> Enum.map(fn {a, b} -> a * b end) |> Enum.sum()
    mag1 = :math.sqrt(Enum.map(v1, &(&1 * &1)) |> Enum.sum())
    mag2 = :math.sqrt(Enum.map(v2, &(&1 * &1)) |> Enum.sum())

    if mag1 == 0 or mag2 == 0 do
      0.0
    else
      dot / (mag1 * mag2)
    end
  end

  @doc """
  Calculates euclidean distance between two embeddings.
  """
  @spec euclidean_distance(t() | [float()], t() | [float()]) :: float()
  def euclidean_distance(%__MODULE__{vector: v1}, %__MODULE__{vector: v2}) do
    euclidean_distance(v1, v2)
  end

  def euclidean_distance(v1, v2) when is_list(v1) and is_list(v2) do
    Enum.zip(v1, v2)
    |> Enum.map(fn {a, b} -> (a - b) * (a - b) end)
    |> Enum.sum()
    |> :math.sqrt()
  end

  # Private functions

  defp make_request(body) do
    base_url = Config.base_url(:openai) || "https://api.openai.com/v1"
    api_key = Config.api_key(:openai)

    Req.post(
      base_url <> "/embeddings",
      json: body,
      headers: [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ],
      receive_timeout: 60_000
    )
  end

  defp parse_response(body, model) do
    usage = body["usage"] || %{}
    input_tokens = usage["prompt_tokens"]

    body["data"]
    |> Enum.sort_by(& &1["index"])
    |> Enum.map(fn item ->
      %__MODULE__{
        vector: item["embedding"],
        model: model,
        input_tokens: input_tokens
      }
    end)
  end

  defp parse_error(status, body) when is_map(body) do
    message = get_in(body, ["error", "message"]) || "Unknown error"
    %{status: status, message: message}
  end

  defp parse_error(status, _body) do
    %{status: status, message: "Request failed"}
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
