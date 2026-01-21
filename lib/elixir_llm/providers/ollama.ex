defmodule ElixirLLM.Providers.Ollama do
  @moduledoc """
  Ollama API provider implementation.

  Runs LLMs locally using Ollama.

  ## Configuration

      config :elixir_llm,
        ollama: [
          base_url: "http://localhost:11434",
          timeout: 300_000  # optional, longer for local inference
        ]

  ## Model Names

  Use local model names directly:

      ElixirLLM.new()
      |> ElixirLLM.model("llama3.2")
      |> ElixirLLM.ask("Hello!")

  Available models depend on what you've pulled with `ollama pull`.
  """

  @behaviour ElixirLLM.Provider

  alias ElixirLLM.{Chat, Chunk, Config, Response, Telemetry, ToolCall}
  alias ElixirLLM.Error.Helpers, as: ErrorHelpers
  alias ElixirLLM.Providers.Base

  @default_base_url "http://localhost:11434"
  @provider :ollama

  @impl true
  def chat(%Chat{} = chat) do
    metadata = %{provider: @provider, model: chat.model}

    Telemetry.span(:chat, metadata, fn ->
      body = build_request_body(chat, stream: false)

      case make_request("/api/chat", body) do
        {:ok, %{status: 200, body: response_body}} ->
          response = parse_response(response_body)
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
    metadata = %{provider: @provider, model: chat.model}
    body = build_request_body(chat, stream: true)

    Telemetry.span(:stream, metadata, fn ->
      case make_stream_request("/api/chat", body, callback) do
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
    message = body["message"] || %{}

    Response.new(
      content: message["content"],
      tool_calls: parse_tool_calls(message["tool_calls"]),
      model: body["model"],
      input_tokens: get_in(body, ["prompt_eval_count"]),
      output_tokens: get_in(body, ["eval_count"]),
      total_tokens: calculate_tokens(body),
      finish_reason: parse_done_reason(body)
    )
  end

  @impl true
  def parse_chunk(data) do
    message = data["message"] || %{}

    Chunk.new(
      content: message["content"],
      tool_calls: parse_tool_calls(message["tool_calls"]),
      model: data["model"],
      input_tokens: get_in(data, ["prompt_eval_count"]),
      output_tokens: get_in(data, ["eval_count"]),
      finish_reason: parse_done_reason(data)
    )
  end

  # Private functions

  defp build_request_body(%Chat{} = chat, opts) do
    body = %{
      model: chat.model,
      messages: format_messages(chat.messages),
      stream: Keyword.get(opts, :stream, false)
    }

    body
    |> maybe_add_options(chat)
    |> Base.maybe_add_tools(chat.tools, &format_tools/1)
    |> Map.merge(chat.params)
  end

  defp maybe_add_options(body, chat) do
    options =
      %{}
      |> Base.maybe_add(:temperature, chat.temperature)
      |> Base.maybe_add(:num_predict, chat.max_tokens)

    if map_size(options) > 0 do
      Map.put(body, :options, options)
    else
      body
    end
  end

  defp format_messages(messages) do
    Enum.map(messages, &format_message/1)
  end

  defp format_message(%{role: :user, content: content}) do
    %{role: "user", content: content}
  end

  defp format_message(%{role: :assistant, content: content, tool_calls: nil}) do
    %{role: "assistant", content: content}
  end

  defp format_message(%{role: :assistant, content: content, tool_calls: tool_calls}) do
    msg = %{role: "assistant", content: content || ""}

    if tool_calls != nil and tool_calls != [] do
      Map.put(msg, :tool_calls, Enum.map(tool_calls, &format_tool_call/1))
    else
      msg
    end
  end

  defp format_message(%{role: :system, content: content}) do
    %{role: "system", content: content}
  end

  defp format_message(%{role: :tool, content: content, tool_call_id: _tool_call_id}) do
    # Ollama uses a simpler format for tool results
    %{role: "tool", content: content}
  end

  defp format_tool_call(%ToolCall{name: name, arguments: args}) do
    %{
      function: %{
        name: name,
        arguments: args
      }
    }
  end

  defp parse_tool_calls(nil), do: nil
  defp parse_tool_calls([]), do: nil

  defp parse_tool_calls(tool_calls) when is_list(tool_calls) do
    Enum.map(tool_calls, fn tc ->
      func = tc["function"] || %{}
      args = normalize_tool_arguments(func["arguments"] || %{})

      ToolCall.new(
        tc["id"] || "call_#{:erlang.unique_integer([:positive])}",
        func["name"],
        args
      )
    end)
  end

  defp normalize_tool_arguments(str) when is_binary(str) do
    case Jason.decode(str) do
      {:ok, decoded} -> decoded
      {:error, _} -> %{}
    end
  end

  defp normalize_tool_arguments(map) when is_map(map), do: map

  defp parse_done_reason(%{"done" => true, "done_reason" => reason}) do
    Base.parse_finish_reason(reason)
  end

  defp parse_done_reason(%{"done" => true}), do: :stop
  defp parse_done_reason(_), do: nil

  defp calculate_tokens(body) do
    prompt = body["prompt_eval_count"]
    eval = body["eval_count"]

    if prompt && eval do
      prompt + eval
    else
      nil
    end
  end

  defp make_request(path, body) do
    base_url = Config.base_url(@provider) || @default_base_url
    timeout = Base.get_timeout(@provider)

    Req.post(
      base_url <> path,
      json: body,
      headers: [{"content-type", "application/json"}],
      receive_timeout: timeout
    )
  end

  defp make_stream_request(path, body, callback) do
    base_url = Config.base_url(@provider) || @default_base_url
    timeout = Base.get_timeout(@provider)

    # Initialize accumulator in process dictionary
    Base.init_stream_accumulator()

    into_fun = Base.create_ndjson_stream_fun(callback, &parse_chunk/1)

    case Req.post(
           base_url <> path,
           json: body,
           headers: [{"content-type", "application/json"}],
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
