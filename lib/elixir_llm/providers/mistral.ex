defmodule ElixirLLM.Providers.Mistral do
  @moduledoc """
  Mistral AI API provider implementation.

  Supports Mistral's hosted models via their official API.

  ## Configuration

      config :elixir_llm,
        mistral: [
          api_key: System.get_env("MISTRAL_API_KEY"),
          timeout: 120_000  # optional
        ]

  ## Model Names

  Use Mistral model identifiers directly or with the `mistral-api/` prefix:

      ElixirLLM.new()
      |> ElixirLLM.model("mistral-large-latest")
      |> ElixirLLM.ask("Hello!")

  Available models:
    * `mistral-large-latest` - Flagship model
    * `mistral-medium-latest` - Balanced performance
    * `mistral-small-latest` - Fast and efficient
    * `codestral-latest` - Code-specialized model
    * `open-mistral-nemo` - Open-weight Nemo model
  """

  @behaviour ElixirLLM.Provider

  alias ElixirLLM.{Chat, Config, Telemetry}
  alias ElixirLLM.Error.Helpers, as: ErrorHelpers
  alias ElixirLLM.Providers.Base

  @default_base_url "https://api.mistral.ai/v1"
  @provider :mistral

  @impl true
  def chat(%Chat{} = chat) do
    model = normalize_model(chat.model)
    metadata = %{provider: @provider, model: model}

    Telemetry.span(:chat, metadata, fn ->
      body = build_request_body(chat, stream: false)

      case make_request("/chat/completions", body) do
        {:ok, %{status: 200, body: response_body}} ->
          response = Base.parse_chat_response(response_body)
          Telemetry.emit(:chat_complete, %{tokens: response.total_tokens}, metadata)
          {:ok, response}

        {:ok, %{status: status, body: body}} ->
          error = Base.parse_error(status, body, @provider)
          Telemetry.emit(:chat_error, %{error: error}, metadata)
          {:error, error}

        {:error, reason} ->
          error = ErrorHelpers.from_transport_error(reason, @provider)
          Telemetry.emit(:chat_error, %{error: error}, metadata)
          {:error, error}
      end
    end)
  end

  @impl true
  def stream(%Chat{} = chat, callback) when is_function(callback, 1) do
    model = normalize_model(chat.model)
    metadata = %{provider: @provider, model: model}
    body = build_request_body(chat, stream: true)

    Telemetry.span(:stream, metadata, fn ->
      case make_stream_request("/chat/completions", body, callback) do
        {:ok, response} ->
          {:ok, response}

        {:error, reason} ->
          Telemetry.emit(:stream_error, %{error: reason}, metadata)
          {:error, reason}
      end
    end)
  end

  @impl true
  def format_tools(tools), do: Base.format_tools_openai(tools)

  @impl true
  def parse_response(body), do: Base.parse_chat_response(body)

  @impl true
  def parse_chunk(data), do: Base.parse_stream_chunk(data)

  # Private functions

  defp normalize_model("mistral-api/" <> model), do: model
  defp normalize_model(model), do: model

  defp build_request_body(%Chat{} = chat, opts) do
    model = normalize_model(chat.model || "mistral-large-latest")

    %{
      model: model,
      messages: Base.format_messages_openai(chat.messages)
    }
    |> Base.maybe_add(:temperature, chat.temperature)
    |> Base.maybe_add(:max_tokens, chat.max_tokens)
    |> Base.maybe_add(:stream, Keyword.get(opts, :stream, false))
    |> Base.maybe_add_tools(chat.tools, &format_tools/1)
    |> Map.merge(chat.params)
  end

  defp make_request(path, body) do
    base_url = Config.base_url(@provider) || @default_base_url
    api_key = Config.api_key(@provider)
    timeout = Base.get_timeout(@provider)

    Req.post(
      base_url <> path,
      json: body,
      headers: Base.bearer_headers(api_key),
      receive_timeout: timeout
    )
  end

  defp make_stream_request(path, body, callback) do
    base_url = Config.base_url(@provider) || @default_base_url
    api_key = Config.api_key(@provider)
    timeout = Base.get_timeout(@provider)

    # Initialize accumulator in process dictionary
    Base.init_stream_accumulator()

    into_fun = Base.create_sse_stream_fun(callback, &parse_chunk/1)

    case Req.post(
           base_url <> path,
           json: body,
           headers: Base.bearer_headers(api_key),
           receive_timeout: timeout,
           into: into_fun
         ) do
      {:ok, %{status: 200}} ->
        final_acc = Base.get_stream_accumulator()
        {:ok, Base.build_final_response(final_acc)}

      {:ok, %{status: status, body: error_body}} ->
        Base.get_stream_accumulator()
        {:error, Base.parse_error(status, error_body, @provider)}

      {:error, reason} ->
        Base.get_stream_accumulator()
        {:error, ErrorHelpers.from_transport_error(reason, @provider)}
    end
  end
end
