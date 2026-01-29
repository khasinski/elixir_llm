defmodule ElixirLLM.Providers.Base do
  @moduledoc """
  Base functionality shared across all LLM providers.

  This module extracts common patterns to eliminate duplication across provider
  implementations. Providers can use these helpers directly or override as needed.

  ## Usage

      defmodule MyProvider do
        alias ElixirLLM.Providers.Base

        # Use shared helpers
        defp parse_error(status, body), do: Base.parse_error(status, body, :my_provider)
        defp accumulate_chunk(acc, chunk), do: Base.accumulate_chunk(acc, chunk)
      end
  """

  alias ElixirLLM.{Chunk, Config, Error, Response, ToolCall}

  # ===========================================================================
  # Streaming Accumulation
  # ===========================================================================

  @doc """
  Initial accumulator state for streaming responses.
  """
  @spec initial_accumulator() :: map()
  def initial_accumulator do
    %{
      content: "",
      tool_calls: [],
      model: nil,
      input_tokens: nil,
      output_tokens: nil,
      finish_reason: nil,
      thinking: ""
    }
  end

  @doc """
  Accumulates a chunk into the streaming state.
  """
  @spec accumulate_chunk(map(), Chunk.t()) :: map()
  def accumulate_chunk(acc, chunk) do
    %{
      acc
      | content: (acc.content || "") <> (chunk.content || ""),
        tool_calls: merge_tool_calls(acc.tool_calls, chunk.tool_calls),
        model: chunk.model || acc.model,
        input_tokens: chunk.input_tokens || acc.input_tokens,
        output_tokens: chunk.output_tokens || acc.output_tokens,
        finish_reason: chunk.finish_reason || acc.finish_reason,
        thinking: (acc.thinking || "") <> (chunk.thinking || "")
    }
  end

  @doc """
  Merges tool calls from streaming chunks.
  """
  @spec merge_tool_calls(list(), list() | nil) :: list()
  def merge_tool_calls(existing, nil), do: existing
  def merge_tool_calls(existing, []), do: existing
  def merge_tool_calls(existing, new), do: existing ++ new

  @doc """
  Builds the final Response from accumulated streaming state.
  """
  @spec build_final_response(map()) :: Response.t()
  def build_final_response(acc) do
    Response.new(
      content: if(acc.content == "", do: nil, else: acc.content),
      tool_calls: if(acc.tool_calls == [], do: nil, else: acc.tool_calls),
      model: acc.model,
      input_tokens: acc.input_tokens,
      output_tokens: acc.output_tokens,
      total_tokens: calculate_total_tokens(acc.input_tokens, acc.output_tokens),
      finish_reason: acc.finish_reason,
      thinking: if(acc[:thinking] in ["", nil], do: nil, else: acc.thinking)
    )
  end

  defp calculate_total_tokens(nil, _), do: nil
  defp calculate_total_tokens(_, nil), do: nil
  defp calculate_total_tokens(input, output), do: input + output

  # ===========================================================================
  # SSE Parsing
  # ===========================================================================

  @doc """
  Parses Server-Sent Events (SSE) data format.

  Handles the standard `data: {...}` format used by OpenAI, Anthropic, and most providers.
  """
  @spec parse_sse_data(String.t()) :: [map()]
  def parse_sse_data(data) do
    data
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "data: "))
    |> Enum.map(&String.trim_leading(&1, "data: "))
    |> Enum.reject(&(&1 in ["[DONE]", ""]))
    |> Enum.map(&decode_json/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Parses newline-delimited JSON (NDJSON) format.

  Used by Ollama and some other providers that don't use SSE.
  """
  @spec parse_ndjson_data(String.t()) :: [map()]
  def parse_ndjson_data(data) do
    data
    |> String.split("\n")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn line ->
      # Handle both SSE format and plain NDJSON
      json =
        if String.starts_with?(line, "data: ") do
          String.trim_leading(line, "data: ")
        else
          line
        end

      decode_json(json)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp decode_json(json) do
    case Jason.decode(json) do
      {:ok, parsed} -> parsed
      {:error, _} -> nil
    end
  end

  # ===========================================================================
  # Error Handling - Returns Structured Errors
  # ===========================================================================

  @doc """
  Parses an error response and returns a structured error.

  This converts provider-specific error responses into ElixirLLM's structured
  error types for consistent error handling.
  """
  @spec parse_error(integer(), map() | term(), atom()) :: struct()
  def parse_error(status, body, provider) when is_map(body) do
    message = extract_error_message(body)
    Error.Helpers.from_response(status, message, provider: provider, body: body)
  end

  def parse_error(status, body, provider) do
    Error.Helpers.from_response(status, "Request failed", provider: provider, body: body)
  end

  defp extract_error_message(body) do
    # Try common error message locations across providers
    get_in(body, ["error", "message"]) ||
      get_in(body, ["error", "msg"]) ||
      body["message"] ||
      body["detail"] ||
      "Unknown error"
  end

  # ===========================================================================
  # Finish Reason Parsing
  # ===========================================================================

  @doc """
  Parses finish reason strings into atoms.
  """
  @spec parse_finish_reason(String.t() | nil) :: atom() | nil
  def parse_finish_reason(nil), do: nil
  def parse_finish_reason("stop"), do: :stop
  def parse_finish_reason("end_turn"), do: :stop
  def parse_finish_reason("length"), do: :length
  def parse_finish_reason("max_tokens"), do: :length
  def parse_finish_reason("tool_calls"), do: :tool_calls
  def parse_finish_reason("tool_use"), do: :tool_calls
  def parse_finish_reason("content_filter"), do: :content_filter
  def parse_finish_reason("STOP"), do: :stop
  def parse_finish_reason("MAX_TOKENS"), do: :length
  def parse_finish_reason(other) when is_binary(other), do: String.to_atom(other)
  def parse_finish_reason(_), do: nil

  # ===========================================================================
  # Tool Call Parsing (OpenAI-compatible format)
  # ===========================================================================

  @doc """
  Parses tool calls from OpenAI-compatible format.

  Most providers (OpenAI, Groq, Mistral, Together, OpenRouter) use this format.
  """
  @spec parse_tool_calls(list() | nil) :: [ToolCall.t()] | nil
  def parse_tool_calls(nil), do: nil
  def parse_tool_calls([]), do: nil

  def parse_tool_calls(tool_calls) when is_list(tool_calls) do
    Enum.map(tool_calls, fn tc ->
      args = decode_tool_arguments(tc["function"]["arguments"])

      ToolCall.new(
        tc["id"],
        tc["function"]["name"],
        args
      )
    end)
  end

  defp decode_tool_arguments(nil), do: %{}

  defp decode_tool_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, decoded} -> decoded
      {:error, _} -> %{}
    end
  end

  defp decode_tool_arguments(args) when is_map(args), do: args

  # ===========================================================================
  # Tool Formatting (OpenAI-compatible format)
  # ===========================================================================

  @doc """
  Formats tools for OpenAI-compatible APIs.

  Most providers accept this format directly.
  """
  @spec format_tools_openai(list()) :: [map()]
  def format_tools_openai(tools) do
    Enum.map(tools, &format_tool_openai/1)
  end

  defp format_tool_openai(tool) when is_atom(tool) do
    %{
      type: "function",
      function: %{
        name: tool.name(),
        description: tool.description(),
        parameters: format_parameters(tool.parameters())
      }
    }
  end

  defp format_tool_openai(%{name: name, description: desc, parameters: params}) do
    %{
      type: "function",
      function: %{
        name: name,
        description: desc,
        parameters: format_parameters(params)
      }
    }
  end

  @doc """
  Formats tool parameters as JSON Schema.
  """
  @spec format_parameters(map()) :: map()
  def format_parameters(params) when is_map(params) do
    properties =
      Enum.reduce(params, %{}, fn {name, opts}, acc ->
        prop = %{type: to_string(Keyword.get(opts, :type, :string))}

        prop =
          if desc = Keyword.get(opts, :description),
            do: Map.put(prop, :description, desc),
            else: prop

        Map.put(acc, name, prop)
      end)

    required =
      params
      |> Enum.filter(fn {_, opts} -> Keyword.get(opts, :required, true) end)
      |> Enum.map(fn {name, _} -> to_string(name) end)

    %{
      type: "object",
      properties: properties,
      required: required
    }
  end

  # ===========================================================================
  # Message Formatting (OpenAI-compatible format)
  # ===========================================================================

  @doc """
  Formats messages for OpenAI-compatible APIs.
  """
  @spec format_messages_openai(list()) :: [map()]
  def format_messages_openai(messages) do
    Enum.map(messages, &format_message_openai/1)
  end

  defp format_message_openai(%{role: :user, content: content}) do
    %{role: "user", content: content}
  end

  defp format_message_openai(%{role: :assistant, content: content, tool_calls: nil}) do
    %{role: "assistant", content: content}
  end

  defp format_message_openai(%{role: :assistant, content: content, tool_calls: tool_calls}) do
    msg = %{role: "assistant", content: content || ""}

    if tool_calls != nil and tool_calls != [] do
      Map.put(msg, :tool_calls, Enum.map(tool_calls, &format_tool_call_for_message/1))
    else
      msg
    end
  end

  defp format_message_openai(%{role: :system, content: content}) do
    %{role: "system", content: content}
  end

  defp format_message_openai(%{role: :tool, content: content, tool_call_id: tool_call_id}) do
    %{role: "tool", content: content, tool_call_id: tool_call_id}
  end

  defp format_tool_call_for_message(%ToolCall{id: id, name: name, arguments: args}) do
    %{
      id: id,
      type: "function",
      function: %{
        name: name,
        arguments: Jason.encode!(args)
      }
    }
  end

  # ===========================================================================
  # Request Building Helpers
  # ===========================================================================

  @doc """
  Conditionally adds a key-value pair to a map if value is not nil.
  """
  @spec maybe_add(map(), atom(), term()) :: map()
  def maybe_add(map, _key, nil), do: map
  def maybe_add(map, key, value), do: Map.put(map, key, value)

  @doc """
  Adds tools to request body if any are registered.
  """
  @spec maybe_add_tools(map(), list(), (list() -> list())) :: map()
  def maybe_add_tools(map, [], _format_fn), do: map

  def maybe_add_tools(map, tools, format_fn) do
    Map.put(map, :tools, format_fn.(tools))
  end

  # ===========================================================================
  # HTTP Request Helpers
  # ===========================================================================

  @doc """
  Gets the configured timeout for a provider.
  """
  @spec get_timeout(atom()) :: pos_integer()
  def get_timeout(provider) do
    config = Config.provider_config(provider)
    Keyword.get(config, :timeout, default_timeout(provider))
  end

  defp default_timeout(:ollama), do: 300_000
  defp default_timeout(:groq), do: 60_000
  defp default_timeout(_), do: 120_000

  @doc """
  Builds standard Bearer token headers.

  Validates that the API key is present and raises a clear error if not.
  """
  @spec bearer_headers(String.t() | nil) :: [{String.t(), String.t()}]
  def bearer_headers(nil) do
    raise ArgumentError, """
    API key is not configured.

    Set the appropriate environment variable or configure in config.exs:

        config :elixir_llm,
          openai: [api_key: System.get_env("OPENAI_API_KEY")]

    Or for other providers:
      - ANTHROPIC_API_KEY
      - GOOGLE_API_KEY (for Gemini)
      - MISTRAL_API_KEY
      - GROQ_API_KEY
      - TOGETHER_API_KEY
      - OPENROUTER_API_KEY
    """
  end

  def bearer_headers("") do
    raise ArgumentError, "API key is empty. Check your configuration."
  end

  def bearer_headers(api_key) when is_binary(api_key) do
    [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]
  end

  @doc """
  Validates that an API key is configured and returns it.

  Raises ArgumentError with a helpful message if the key is missing.
  """
  @spec require_api_key!(atom()) :: String.t()
  def require_api_key!(provider) do
    case Config.api_key(provider) do
      nil ->
        env_var = Config.provider_env_var(provider)

        raise ArgumentError, """
        API key not configured for #{provider}.

        Set the #{env_var} environment variable or configure in config.exs:

            config :elixir_llm,
              #{provider}: [api_key: System.get_env("#{env_var}")]
        """

      "" ->
        raise ArgumentError, "API key for #{provider} is empty. Check your configuration."

      api_key when is_binary(api_key) ->
        api_key
    end
  end

  # ===========================================================================
  # Streaming with Process Dictionary Pattern
  # ===========================================================================

  @stream_acc_key :elixir_llm_stream_accumulator

  @doc """
  Creates a streaming function that processes SSE chunks.

  Uses process dictionary to accumulate state since Req 0.5.x `into:` option
  only supports functions with `{:data, data}, {req, resp}` signature.
  """
  @spec create_sse_stream_fun((Chunk.t() -> any()), (map() -> Chunk.t() | nil)) ::
          ({:data, binary()}, {term(), term()} -> {:cont, {term(), term()}})
  def create_sse_stream_fun(callback, parse_chunk_fn) do
    fn {:data, data}, {req, resp} ->
      chunks = parse_sse_data(data)
      Enum.each(chunks, &process_stream_chunk(&1, callback, parse_chunk_fn))
      {:cont, {req, resp}}
    end
  end

  @doc """
  Creates a streaming function for NDJSON format.
  """
  @spec create_ndjson_stream_fun((Chunk.t() -> any()), (map() -> Chunk.t() | nil)) ::
          ({:data, binary()}, {term(), term()} -> {:cont, {term(), term()}})
  def create_ndjson_stream_fun(callback, parse_chunk_fn) do
    fn {:data, data}, {req, resp} ->
      chunks = parse_ndjson_data(data)
      Enum.each(chunks, &process_stream_chunk(&1, callback, parse_chunk_fn))
      {:cont, {req, resp}}
    end
  end

  @doc """
  Initializes the stream accumulator in the process dictionary.
  Must be called before starting a stream request.
  """
  @spec init_stream_accumulator() :: :ok
  def init_stream_accumulator do
    Process.put(@stream_acc_key, initial_accumulator())
    :ok
  end

  @doc """
  Gets and clears the stream accumulator from the process dictionary.
  Returns the final accumulated state.
  """
  @spec get_stream_accumulator() :: map()
  def get_stream_accumulator do
    acc = Process.get(@stream_acc_key, initial_accumulator())
    Process.delete(@stream_acc_key)
    acc
  end

  defp process_stream_chunk(chunk_data, callback, parse_chunk_fn) do
    case parse_chunk_fn.(chunk_data) do
      nil ->
        :ok

      chunk ->
        callback.(chunk)
        acc = Process.get(@stream_acc_key, initial_accumulator())
        Process.put(@stream_acc_key, accumulate_chunk(acc, chunk))
    end
  end

  # Legacy fold functions (kept for backwards compatibility, but use stream functions instead)

  @doc """
  Creates a streaming fold function that processes SSE chunks.
  @deprecated Use create_sse_stream_fun/2 instead
  """
  @spec create_sse_fold_fun((Chunk.t() -> any()), (map() -> Chunk.t() | nil)) ::
          (term(), {term(), term(), map()} -> {:cont, {term(), term(), map()}})
  def create_sse_fold_fun(callback, parse_chunk_fn) do
    fn {:data, data}, {req, resp, acc} ->
      chunks = parse_sse_data(data)
      new_acc = Enum.reduce(chunks, acc, &process_fold_chunk(&1, &2, callback, parse_chunk_fn))
      {:cont, {req, resp, new_acc}}
    end
  end

  @doc """
  Creates a streaming fold function for NDJSON format.
  @deprecated Use create_ndjson_stream_fun/2 instead
  """
  @spec create_ndjson_fold_fun((Chunk.t() -> any()), (map() -> Chunk.t() | nil)) ::
          (term(), {term(), term(), map()} -> {:cont, {term(), term(), map()}})
  def create_ndjson_fold_fun(callback, parse_chunk_fn) do
    fn {:data, data}, {req, resp, acc} ->
      chunks = parse_ndjson_data(data)
      new_acc = Enum.reduce(chunks, acc, &process_fold_chunk(&1, &2, callback, parse_chunk_fn))
      {:cont, {req, resp, new_acc}}
    end
  end

  defp process_fold_chunk(chunk_data, current_acc, callback, parse_chunk_fn) do
    case parse_chunk_fn.(chunk_data) do
      nil ->
        current_acc

      chunk ->
        callback.(chunk)
        accumulate_chunk(current_acc, chunk)
    end
  end

  # ===========================================================================
  # Response Parsing Helpers
  # ===========================================================================

  @doc """
  Parses a standard OpenAI-compatible chat completion response.
  """
  @spec parse_chat_response(map(), (list() | nil -> [ToolCall.t()] | nil)) :: Response.t()
  def parse_chat_response(body, parse_tool_calls_fn \\ &parse_tool_calls/1) do
    choice = List.first(body["choices"] || [])
    message = (choice && choice["message"]) || %{}
    usage = body["usage"] || %{}

    Response.new(
      content: message["content"],
      tool_calls: parse_tool_calls_fn.(message["tool_calls"]),
      model: body["model"],
      input_tokens: usage["prompt_tokens"],
      output_tokens: usage["completion_tokens"],
      total_tokens: usage["total_tokens"],
      finish_reason: parse_finish_reason(choice && choice["finish_reason"])
    )
  end

  @doc """
  Parses a standard OpenAI-compatible streaming chunk.
  """
  @spec parse_stream_chunk(map(), (list() | nil -> [ToolCall.t()] | nil)) :: Chunk.t() | nil
  def parse_stream_chunk(data, parse_tool_calls_fn \\ &parse_tool_calls/1) do
    choice = List.first(data["choices"] || [])

    if is_nil(choice) do
      nil
    else
      delta = choice["delta"] || %{}
      usage = data["usage"]

      Chunk.new(
        content: delta["content"],
        tool_calls: parse_tool_calls_fn.(delta["tool_calls"]),
        model: data["model"],
        input_tokens: usage && usage["prompt_tokens"],
        output_tokens: usage && usage["completion_tokens"],
        finish_reason: parse_finish_reason(choice["finish_reason"])
      )
    end
  end
end
