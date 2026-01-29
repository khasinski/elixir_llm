defmodule ElixirLLM.Providers.DeepSeek do
  @moduledoc """
  DeepSeek API provider implementation.

  Supports DeepSeek Chat, DeepSeek Reasoner (R1), and DeepSeek Coder.
  Uses OpenAI-compatible API format.

  ## Configuration

      config :elixir_llm,
        deepseek: [
          api_key: System.get_env("DEEPSEEK_API_KEY"),
          base_url: "https://api.deepseek.com",  # optional
          timeout: 120_000  # optional, in milliseconds
        ]

  ## Model Names

  Models can be specified with or without the `deepseek/` prefix:

      ElixirLLM.new() |> ElixirLLM.model("deepseek-chat")
      ElixirLLM.new() |> ElixirLLM.model("deepseek/deepseek-chat")
      ElixirLLM.new() |> ElixirLLM.model("deepseek-reasoner")  # R1 reasoning model

  ## Extended Thinking

  The `deepseek-reasoner` model supports extended thinking (chain-of-thought).
  The thinking content is returned in the response when available.
  """

  @behaviour ElixirLLM.Provider

  alias ElixirLLM.{Chat, Config, Telemetry}
  alias ElixirLLM.Error.Helpers, as: ErrorHelpers
  alias ElixirLLM.Providers.Base

  @default_base_url "https://api.deepseek.com"
  @provider :deepseek

  @impl true
  def chat(%Chat{} = chat) do
    start_time = System.monotonic_time()
    model = normalize_model(chat.model)
    metadata = %{provider: @provider, model: model}

    Telemetry.span(:chat, metadata, fn ->
      body = build_request_body(chat, stream: false)

      case make_request("/chat/completions", body) do
        {:ok, %{status: 200, body: response_body}} ->
          response = parse_response(response_body)
          duration = System.monotonic_time() - start_time

          Telemetry.emit(
            :chat_complete,
            %{duration: duration, tokens: response.total_tokens},
            metadata
          )

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
  def parse_response(body) do
    # DeepSeek Reasoner returns reasoning_content in the message
    response = Base.parse_chat_response(body)

    # Extract thinking/reasoning content if present
    thinking = extract_thinking(body)

    if thinking do
      %{response | thinking: thinking}
    else
      response
    end
  end

  @impl true
  def parse_chunk(data) do
    # Standard chunk parsing, DeepSeek uses OpenAI format
    Base.parse_stream_chunk(data)
  end

  # Private functions

  defp normalize_model("deepseek/" <> model), do: model
  defp normalize_model(model), do: model

  defp extract_thinking(body) do
    # DeepSeek Reasoner includes reasoning_content in the message
    body
    |> get_in(["choices", Access.at(0), "message", "reasoning_content"])
  end

  defp build_request_body(%Chat{} = chat, opts) do
    model = normalize_model(chat.model)

    body = %{
      model: model,
      messages: Base.format_messages_openai(chat.messages)
    }

    body =
      body
      |> Base.maybe_add(:temperature, chat.temperature)
      |> Base.maybe_add(:max_tokens, chat.max_tokens)
      |> Base.maybe_add(:stream, Keyword.get(opts, :stream, false))
      |> Base.maybe_add_tools(chat.tools, &format_tools/1)
      |> Map.merge(chat.params)

    # Add stream options for token usage in streaming
    if Keyword.get(opts, :stream, false) do
      Map.put(body, :stream_options, %{include_usage: true})
    else
      body
    end
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
