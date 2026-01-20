defmodule ElixirLLM.Providers.OpenAI do
  @moduledoc """
  OpenAI API provider implementation.

  Supports GPT-4, GPT-4o, o1, o3, and other OpenAI models.
  """

  @behaviour ElixirLLM.Provider

  alias ElixirLLM.{Chat, Response, Chunk, ToolCall, Config, Telemetry}

  @default_base_url "https://api.openai.com/v1"

  @impl true
  def chat(%Chat{} = chat) do
    start_time = System.monotonic_time()
    metadata = %{provider: :openai, model: chat.model}

    Telemetry.span(:chat, metadata, fn ->
      body = build_request_body(chat, stream: false)

      case make_request("/chat/completions", body, chat) do
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
    metadata = %{provider: :openai, model: chat.model}
    body = build_request_body(chat, stream: true)

    Telemetry.span(:stream, metadata, fn ->
      case make_stream_request("/chat/completions", body, chat, callback) do
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
    choice = List.first(body["choices"] || [])
    message = choice["message"] || %{}
    usage = body["usage"] || %{}

    Response.new(
      content: message["content"],
      tool_calls: parse_tool_calls(message["tool_calls"]),
      model: body["model"],
      input_tokens: usage["prompt_tokens"],
      output_tokens: usage["completion_tokens"],
      total_tokens: usage["total_tokens"],
      finish_reason: parse_finish_reason(choice["finish_reason"])
    )
  end

  @impl true
  def parse_chunk(data) do
    choice = List.first(data["choices"] || [])

    if is_nil(choice) do
      nil
    else
      delta = choice["delta"] || %{}
      usage = data["usage"]

      Chunk.new(
        content: delta["content"],
        tool_calls: parse_tool_calls(delta["tool_calls"]),
        model: data["model"],
        input_tokens: usage && usage["prompt_tokens"],
        output_tokens: usage && usage["completion_tokens"],
        finish_reason: parse_finish_reason(choice["finish_reason"])
      )
    end
  end

  # Private functions

  defp build_request_body(%Chat{} = chat, opts) do
    body = %{
      model: chat.model || Config.default_model(),
      messages: format_messages(chat.messages)
    }

    body =
      body
      |> maybe_add(:temperature, chat.temperature)
      |> maybe_add(:max_tokens, chat.max_tokens)
      |> maybe_add(:stream, Keyword.get(opts, :stream, false))
      |> maybe_add_tools(chat.tools)
      |> Map.merge(chat.params)

    # Add stream options for token usage in streaming
    if Keyword.get(opts, :stream, false) do
      Map.put(body, :stream_options, %{include_usage: true})
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

    if tool_calls && length(tool_calls) > 0 do
      Map.put(msg, :tool_calls, Enum.map(tool_calls, &format_tool_call_for_message/1))
    else
      msg
    end
  end

  defp format_message(%{role: :system, content: content}) do
    %{role: "system", content: content}
  end

  defp format_message(%{role: :tool, content: content, tool_call_id: tool_call_id}) do
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

  defp format_tool(tool) when is_atom(tool) do
    # Module-based tool
    %{
      type: "function",
      function: %{
        name: tool.name(),
        description: tool.description(),
        parameters: format_parameters(tool.parameters())
      }
    }
  end

  defp format_tool(%{name: name, description: desc, parameters: params, execute: _}) do
    # Inline tool definition
    %{
      type: "function",
      function: %{
        name: name,
        description: desc,
        parameters: format_parameters(params)
      }
    }
  end

  defp format_parameters(params) when is_map(params) do
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

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  defp maybe_add_tools(map, []), do: map

  defp maybe_add_tools(map, tools) do
    Map.put(map, :tools, format_tools(tools))
  end

  defp parse_tool_calls(nil), do: nil
  defp parse_tool_calls([]), do: nil

  defp parse_tool_calls(tool_calls) do
    Enum.map(tool_calls, fn tc ->
      args =
        case Jason.decode(tc["function"]["arguments"] || "{}") do
          {:ok, decoded} -> decoded
          {:error, _} -> %{}
        end

      ToolCall.new(
        tc["id"],
        tc["function"]["name"],
        args
      )
    end)
  end

  defp parse_finish_reason(nil), do: nil
  defp parse_finish_reason("stop"), do: :stop
  defp parse_finish_reason("length"), do: :length
  defp parse_finish_reason("tool_calls"), do: :tool_calls
  defp parse_finish_reason("content_filter"), do: :content_filter
  defp parse_finish_reason(other), do: String.to_atom(other)

  defp parse_error(status, body) when is_map(body) do
    message = get_in(body, ["error", "message"]) || "Unknown error"
    %{status: status, message: message, body: body}
  end

  defp parse_error(status, body) do
    %{status: status, message: "Request failed", body: body}
  end

  defp make_request(path, body, _chat) do
    base_url = Config.base_url(:openai) || @default_base_url
    api_key = Config.api_key(:openai)

    Req.post(
      base_url <> path,
      json: body,
      headers: build_headers(api_key),
      receive_timeout: 120_000
    )
  end

  defp make_stream_request(path, body, _chat, callback) do
    base_url = Config.base_url(:openai) || @default_base_url
    api_key = Config.api_key(:openai)

    # Use process dictionary to accumulate chunks during streaming
    Process.put(:stream_acc, %{
      content: "",
      tool_calls: [],
      model: nil,
      input_tokens: nil,
      output_tokens: nil,
      finish_reason: nil
    })

    into_fun = fn {:data, data}, {req, resp} ->
      chunks = parse_sse_data(data)

      Enum.each(chunks, fn chunk_data ->
        case parse_chunk(chunk_data) do
          nil ->
            :ok

          chunk ->
            # Call the user's callback
            callback.(chunk)

            # Accumulate the response
            acc = Process.get(:stream_acc)
            Process.put(:stream_acc, accumulate_chunk(acc, chunk))
        end
      end)

      {:cont, {req, resp}}
    end

    result =
      case Req.post(
             base_url <> path,
             json: body,
             headers: build_headers(api_key),
             receive_timeout: 120_000,
             into: into_fun
           ) do
        {:ok, %{status: 200}} ->
          final_acc = Process.get(:stream_acc)
          {:ok, build_final_response(final_acc)}

        {:ok, %{status: status, body: body}} ->
          {:error, parse_error(status, body)}

        {:error, reason} ->
          {:error, reason}
      end

    Process.delete(:stream_acc)
    result
  end

  defp build_headers(api_key) do
    [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]
  end

  defp parse_sse_data(data) do
    data
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "data: "))
    |> Enum.map(&String.trim_leading(&1, "data: "))
    |> Enum.reject(&(&1 == "[DONE]"))
    |> Enum.map(fn json ->
      case Jason.decode(json) do
        {:ok, parsed} -> parsed
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp accumulate_chunk(acc, chunk) do
    %{
      acc
      | content: (acc.content || "") <> (chunk.content || ""),
        tool_calls: merge_tool_calls(acc.tool_calls, chunk.tool_calls),
        model: chunk.model || acc.model,
        input_tokens: chunk.input_tokens || acc.input_tokens,
        output_tokens: chunk.output_tokens || acc.output_tokens,
        finish_reason: chunk.finish_reason || acc.finish_reason
    }
  end

  defp merge_tool_calls(existing, nil), do: existing
  defp merge_tool_calls(existing, []), do: existing
  defp merge_tool_calls(existing, new), do: existing ++ new

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
