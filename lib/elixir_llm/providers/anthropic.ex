defmodule ElixirLLM.Providers.Anthropic do
  @moduledoc """
  Anthropic API provider implementation.

  Supports Claude models (claude-3-opus, claude-3-sonnet, claude-3-haiku, etc.).
  """

  @behaviour ElixirLLM.Provider

  alias ElixirLLM.{Chat, Chunk, Config, Response, Telemetry, ToolCall}

  @default_base_url "https://api.anthropic.com"
  @api_version "2023-06-01"

  @impl true
  def chat(%Chat{} = chat) do
    metadata = %{provider: :anthropic, model: chat.model}

    Telemetry.span(:chat, metadata, fn ->
      body = build_request_body(chat, stream: false)

      case make_request("/v1/messages", body, chat) do
        {:ok, %{status: 200, body: response_body}} ->
          response = parse_response(response_body)
          Telemetry.emit(:chat_complete, %{tokens: response.total_tokens}, metadata)
          {:ok, response}

        {:ok, %{status: status, body: body}} ->
          error = parse_error(status, body)
          Telemetry.emit(:chat_error, %{error: error}, metadata)
          {:error, error}

        {:error, reason} ->
          Telemetry.emit(:chat_error, %{error: reason}, metadata)
          {:error, reason}
      end
    end)
  end

  @impl true
  def stream(%Chat{} = chat, callback) when is_function(callback, 1) do
    metadata = %{provider: :anthropic, model: chat.model}
    body = build_request_body(chat, stream: true)

    Telemetry.span(:stream, metadata, fn ->
      case make_stream_request("/v1/messages", body, chat, callback) do
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

    body =
      body
      |> maybe_add(:system, if(system_content != "", do: system_content))
      |> maybe_add(:temperature, chat.temperature)
      |> maybe_add(:stream, Keyword.get(opts, :stream, false))
      |> maybe_add_tools(chat.tools)
      |> Map.merge(chat.params)

    body
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
      input_schema: format_input_schema(tool.parameters())
    }
  end

  defp format_tool(%{name: name, description: desc, parameters: params}) do
    %{
      name: name,
      description: desc,
      input_schema: format_input_schema(params)
    }
  end

  defp format_input_schema(params) when is_map(params) do
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

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

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

  defp parse_error(status, body) when is_map(body) do
    message = get_in(body, ["error", "message"]) || "Unknown error"
    %{status: status, message: message, body: body}
  end

  defp parse_error(status, body) do
    %{status: status, message: "Request failed", body: body}
  end

  defp make_request(path, body, _chat) do
    base_url = Config.base_url(:anthropic) || @default_base_url
    api_key = Config.api_key(:anthropic)

    Req.post(
      base_url <> path,
      json: body,
      headers: build_headers(api_key),
      receive_timeout: 120_000
    )
  end

  defp make_stream_request(path, body, _chat, callback) do
    base_url = Config.base_url(:anthropic) || @default_base_url
    api_key = Config.api_key(:anthropic)

    accumulated = %{
      content: "",
      tool_calls: [],
      model: nil,
      input_tokens: nil,
      output_tokens: nil,
      finish_reason: nil
    }

    into_fun = fn {:data, data}, {req, resp, acc} ->
      events = parse_sse_events(data)

      new_acc =
        Enum.reduce(events, acc, fn event_data, current_acc ->
          case parse_chunk(event_data) do
            nil ->
              current_acc

            chunk ->
              callback.(chunk)
              accumulate_chunk(current_acc, chunk)
          end
        end)

      {:cont, {req, resp, new_acc}}
    end

    case Req.post(
           base_url <> path,
           json: body,
           headers: build_headers(api_key),
           receive_timeout: 120_000,
           into: {:fold, accumulated, into_fun}
         ) do
      {:ok, %{status: 200, body: {_req, _resp, final_acc}}} ->
        {:ok, build_final_response(final_acc)}

      {:ok, %{status: status, body: body}} ->
        {:error, parse_error(status, body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_headers(api_key) do
    [
      {"x-api-key", api_key},
      {"anthropic-version", @api_version},
      {"content-type", "application/json"}
    ]
  end

  defp parse_sse_events(data) do
    data
    |> String.split("\n\n")
    |> Enum.flat_map(&parse_sse_event/1)
  end

  defp parse_sse_event(event_str) do
    lines = String.split(event_str, "\n")

    data_line =
      Enum.find(lines, fn line ->
        String.starts_with?(line, "data: ")
      end)

    case data_line do
      nil ->
        []

      line ->
        json = String.trim_leading(line, "data: ")

        case Jason.decode(json) do
          {:ok, parsed} -> [parsed]
          {:error, _} -> []
        end
    end
  end

  defp accumulate_chunk(acc, chunk) do
    %{
      acc
      | content: (acc.content || "") <> (chunk.content || ""),
        model: chunk.model || acc.model,
        input_tokens: chunk.input_tokens || acc.input_tokens,
        output_tokens: chunk.output_tokens || acc.output_tokens,
        finish_reason: chunk.finish_reason || acc.finish_reason
    }
  end

  defp build_final_response(acc) do
    Response.new(
      content: if(acc.content == "", do: nil, else: acc.content),
      tool_calls: if(acc.tool_calls == [], do: nil, else: acc.tool_calls),
      model: acc.model,
      input_tokens: acc.input_tokens,
      output_tokens: acc.output_tokens,
      total_tokens:
        if(acc.input_tokens && acc.output_tokens,
          do: acc.input_tokens + acc.output_tokens,
          else: nil
        ),
      finish_reason: acc.finish_reason
    )
  end
end
