defmodule ElixirLLM.Providers.Anthropic do
  @moduledoc """
  Anthropic API provider implementation.

  Supports Claude models (claude-3-opus, claude-3-sonnet, claude-3-haiku, etc.).

  ## Configuration

      config :elixir_llm,
        anthropic: [
          api_key: System.get_env("ANTHROPIC_API_KEY"),
          timeout: 120_000  # optional
        ]

  ## Model Names

  Use Anthropic model identifiers:

      ElixirLLM.new()
      |> ElixirLLM.model("claude-sonnet-4-20250514")
      |> ElixirLLM.ask("Hello!")

  Available models:
    * `claude-sonnet-4-20250514` - Latest Claude 4 Sonnet
    * `claude-3-5-sonnet-20241022` - Claude 3.5 Sonnet
    * `claude-3-opus-20240229` - Most capable Claude 3
    * `claude-3-haiku-20240307` - Fast and efficient
  """

  @behaviour ElixirLLM.Provider

  alias ElixirLLM.{Chat, Chunk, Config, Response, Telemetry, ToolCall}
  alias ElixirLLM.Error.Helpers, as: ErrorHelpers
  alias ElixirLLM.Providers.Base

  @default_base_url "https://api.anthropic.com"
  @api_version "2023-06-01"
  @provider :anthropic

  @impl true
  def chat(%Chat{} = chat) do
    metadata = %{provider: @provider, model: chat.model}

    Telemetry.span(:chat, metadata, fn ->
      body = build_request_body(chat, stream: false)

      case make_request("/v1/messages", body) do
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
      case make_stream_request("/v1/messages", body, callback) do
        {:ok, response} ->
          {:ok, response}

        {:error, reason} ->
          Telemetry.emit(:stream_error, %{error: reason}, metadata)
          {:error, reason}
      end
    end)
  end

  @impl true
  def format_tools(tools) do
    Enum.map(tools, &format_tool/1)
  end

  @impl true
  def parse_response(body) do
    content_blocks = body["content"] || []
    usage = body["usage"] || %{}

    {text_content, tool_calls} = extract_content(content_blocks)

    Response.new(
      content: text_content,
      tool_calls: tool_calls,
      model: body["model"],
      input_tokens: usage["input_tokens"],
      output_tokens: usage["output_tokens"],
      total_tokens: (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0),
      finish_reason: parse_stop_reason(body["stop_reason"])
    )
  end

  @impl true
  def parse_chunk(event_data) do
    case event_data do
      %{"type" => "content_block_delta", "delta" => delta} ->
        parse_delta(delta)

      %{"type" => "message_delta", "delta" => delta, "usage" => usage} ->
        Chunk.new(
          finish_reason: parse_stop_reason(delta["stop_reason"]),
          output_tokens: usage["output_tokens"]
        )

      %{"type" => "message_start", "message" => message} ->
        usage = message["usage"] || %{}

        Chunk.new(
          model: message["model"],
          input_tokens: usage["input_tokens"]
        )

      _ ->
        nil
    end
  end

  # Private functions

  defp build_request_body(%Chat{} = chat, opts) do
    {system_messages, other_messages} =
      Enum.split_with(chat.messages, &(&1.role == :system))

    system_content = Enum.map_join(system_messages, "\n\n", & &1.content)

    body = %{
      model: chat.model || "claude-sonnet-4-20250514",
      messages: format_messages(other_messages),
      max_tokens: chat.max_tokens || 4096
    }

    body
    |> Base.maybe_add(:system, if(system_content != "", do: system_content))
    |> Base.maybe_add(:temperature, chat.temperature)
    |> Base.maybe_add(:stream, Keyword.get(opts, :stream, false))
    |> maybe_add_tools(chat.tools)
    |> Map.merge(chat.params)
  end

  defp format_messages(messages) do
    Enum.map(messages, &format_message/1)
  end

  defp format_message(%{role: :user, content: content}) do
    %{role: "user", content: content}
  end

  defp format_message(%{role: :assistant, content: content, tool_calls: nil}) do
    %{role: "assistant", content: [%{type: "text", text: content || ""}]}
  end

  defp format_message(%{role: :assistant, content: content, tool_calls: tool_calls}) do
    content_blocks = []

    content_blocks =
      if content && content != "" do
        content_blocks ++ [%{type: "text", text: content}]
      else
        content_blocks
      end

    content_blocks =
      if tool_calls != nil and tool_calls != [] do
        tool_use_blocks =
          Enum.map(tool_calls, fn tc ->
            %{
              type: "tool_use",
              id: tc.id,
              name: tc.name,
              input: tc.arguments
            }
          end)

        content_blocks ++ tool_use_blocks
      else
        content_blocks
      end

    %{role: "assistant", content: content_blocks}
  end

  defp format_message(%{role: :tool, content: content, tool_call_id: tool_call_id}) do
    %{
      role: "user",
      content: [
        %{
          type: "tool_result",
          tool_use_id: tool_call_id,
          content: content
        }
      ]
    }
  end

  defp format_tool(tool) when is_atom(tool) do
    %{
      name: tool.name(),
      description: tool.description(),
      input_schema: Base.format_parameters(tool.parameters())
    }
  end

  defp format_tool(%{name: name, description: desc, parameters: params}) do
    %{
      name: name,
      description: desc,
      input_schema: Base.format_parameters(params)
    }
  end

  defp extract_content(content_blocks) do
    {texts, tool_uses} =
      Enum.reduce(content_blocks, {[], []}, fn block, {texts, tools} ->
        case block["type"] do
          "text" ->
            {texts ++ [block["text"]], tools}

          "tool_use" ->
            tool_call =
              ToolCall.new(
                block["id"],
                block["name"],
                block["input"] || %{}
              )

            {texts, tools ++ [tool_call]}

          _ ->
            {texts, tools}
        end
      end)

    text_content = Enum.join(texts, "")
    tool_calls = if tool_uses == [], do: nil, else: tool_uses

    {if(text_content == "", do: nil, else: text_content), tool_calls}
  end

  defp parse_delta(%{"type" => "text_delta", "text" => text}) do
    Chunk.new(content: text)
  end

  defp parse_delta(%{"type" => "input_json_delta"}) do
    # Tool input streaming - we'll handle this when we accumulate
    nil
  end

  defp parse_delta(_), do: nil

  defp maybe_add_tools(map, []), do: map

  defp maybe_add_tools(map, tools) do
    Map.put(map, :tools, format_tools(tools))
  end

  defp parse_stop_reason(nil), do: nil
  defp parse_stop_reason("end_turn"), do: :stop
  defp parse_stop_reason("stop_sequence"), do: :stop
  defp parse_stop_reason("max_tokens"), do: :length
  defp parse_stop_reason("tool_use"), do: :tool_calls
  defp parse_stop_reason(other), do: String.to_atom(other)

  defp make_request(path, body) do
    base_url = Config.base_url(@provider) || @default_base_url
    api_key = Base.require_api_key!(@provider)
    timeout = Base.get_timeout(@provider)

    Req.post(
      base_url <> path,
      json: body,
      headers: build_headers(api_key),
      receive_timeout: timeout
    )
  end

  defp make_stream_request(path, body, callback) do
    base_url = Config.base_url(@provider) || @default_base_url
    api_key = Base.require_api_key!(@provider)
    timeout = Base.get_timeout(@provider)

    # Initialize accumulator in process dictionary
    Base.init_stream_accumulator()

    into_fun = fn {:data, data}, {req, resp} ->
      events = Base.parse_sse_data(data)
      Enum.each(events, &process_stream_event(&1, callback))
      {:cont, {req, resp}}
    end

    case Req.post(
           base_url <> path,
           json: body,
           headers: build_headers(api_key),
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

  defp process_stream_event(event_data, callback) do
    case parse_chunk(event_data) do
      nil ->
        :ok

      chunk ->
        callback.(chunk)
        acc = Process.get(:elixir_llm_stream_accumulator, Base.initial_accumulator())
        Process.put(:elixir_llm_stream_accumulator, Base.accumulate_chunk(acc, chunk))
    end
  end

  defp build_headers(api_key) do
    [
      {"x-api-key", api_key},
      {"anthropic-version", @api_version},
      {"content-type", "application/json"}
    ]
  end
end
