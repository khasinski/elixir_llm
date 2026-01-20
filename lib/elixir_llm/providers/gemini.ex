defmodule ElixirLLM.Providers.Gemini do
  @moduledoc """
  Google Gemini API provider implementation.

  Supports Gemini models (gemini-2.0-flash, gemini-1.5-pro, gemini-1.5-flash, etc.).

  ## Configuration

      config :elixir_llm,
        gemini: [
          api_key: System.get_env("GOOGLE_API_KEY")
        ]

  ## Model Names

  Use Gemini model identifiers:

      ElixirLLM.new()
      |> ElixirLLM.model("gemini-2.0-flash")
      |> ElixirLLM.ask("Hello!")

  Available models:
    * `gemini-2.0-flash` - Fast, efficient model
    * `gemini-2.0-flash-thinking` - Enhanced reasoning
    * `gemini-1.5-pro` - Most capable model
    * `gemini-1.5-flash` - Fast and versatile
    * `gemini-1.5-flash-8b` - Lightweight model
  """

  @behaviour ElixirLLM.Provider

  alias ElixirLLM.{Chat, Chunk, Config, Response, Telemetry, ToolCall}

  @default_base_url "https://generativelanguage.googleapis.com/v1beta"

  @impl true
  def chat(%Chat{} = chat) do
    metadata = %{provider: :gemini, model: chat.model}

    Telemetry.span(:chat, metadata, fn ->
      body = build_request_body(chat, stream: false)
      model = chat.model || "gemini-2.0-flash"
      path = "/models/#{model}:generateContent"

      case make_request(path, body, chat) do
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
    metadata = %{provider: :gemini, model: chat.model}
    body = build_request_body(chat, stream: true)
    model = chat.model || "gemini-2.0-flash"
    path = "/models/#{model}:streamGenerateContent"

    Telemetry.span(:stream, metadata, fn ->
      case make_stream_request(path, body, chat, callback) do
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
    function_declarations = Enum.map(tools, &format_tool/1)
    [%{function_declarations: function_declarations}]
  end

  @impl true
  def parse_response(body) do
    candidate = List.first(body["candidates"] || [])
    content = candidate["content"] || %{}
    parts = content["parts"] || []
    usage = body["usageMetadata"] || %{}

    {text_content, tool_calls} = extract_content(parts)

    Response.new(
      content: text_content,
      tool_calls: tool_calls,
      model: body["modelVersion"],
      input_tokens: usage["promptTokenCount"],
      output_tokens: usage["candidatesTokenCount"],
      total_tokens: usage["totalTokenCount"],
      finish_reason: parse_finish_reason(candidate["finishReason"])
    )
  end

  @impl true
  def parse_chunk(data) do
    candidate = List.first(data["candidates"] || [])

    if is_nil(candidate) do
      nil
    else
      content = candidate["content"] || %{}
      parts = content["parts"] || []
      usage = data["usageMetadata"]

      {text_content, tool_calls} = extract_content(parts)

      Chunk.new(
        content: text_content,
        tool_calls: tool_calls,
        model: data["modelVersion"],
        input_tokens: usage && usage["promptTokenCount"],
        output_tokens: usage && usage["candidatesTokenCount"],
        finish_reason: parse_finish_reason(candidate["finishReason"])
      )
    end
  end

  # Private functions

  defp build_request_body(%Chat{} = chat, _opts) do
    {system_messages, other_messages} =
      Enum.split_with(chat.messages, &(&1.role == :system))

    system_instruction =
      case system_messages do
        [] ->
          nil

        msgs ->
          text = Enum.map_join(msgs, "\n\n", & &1.content)
          %{parts: [%{text: text}]}
      end

    body = %{
      contents: format_messages(other_messages),
      generationConfig: build_generation_config(chat)
    }

    body =
      body
      |> maybe_add(:systemInstruction, system_instruction)
      |> maybe_add_tools(chat.tools)

    body
  end

  defp build_generation_config(chat) do
    config = %{}

    config =
      config
      |> maybe_add(:temperature, chat.temperature)
      |> maybe_add(:maxOutputTokens, chat.max_tokens)

    if config == %{}, do: nil, else: config
  end

  defp format_messages(messages) do
    messages
    |> Enum.map(&format_message/1)
    |> merge_consecutive_roles()
  end

  defp format_message(%{role: :user, content: content}) do
    %{role: "user", parts: [%{text: content}]}
  end

  defp format_message(%{role: :assistant, content: content, tool_calls: nil}) do
    %{role: "model", parts: [%{text: content || ""}]}
  end

  defp format_message(%{role: :assistant, content: content, tool_calls: tool_calls}) do
    parts = []

    parts =
      if content && content != "" do
        parts ++ [%{text: content}]
      else
        parts
      end

    parts =
      if tool_calls != nil and tool_calls != [] do
        tool_parts =
          Enum.map(tool_calls, fn tc ->
            %{
              functionCall: %{
                name: tc.name,
                args: tc.arguments
              }
            }
          end)

        parts ++ tool_parts
      else
        parts
      end

    %{role: "model", parts: parts}
  end

  defp format_message(%{role: :tool, content: content, tool_call_id: tool_call_id}) do
    # Gemini expects function responses in user turn
    %{
      role: "user",
      parts: [
        %{
          functionResponse: %{
            name: tool_call_id,
            response: %{result: content}
          }
        }
      ]
    }
  end

  # Gemini requires alternating user/model turns, so merge consecutive same-role messages
  defp merge_consecutive_roles(messages) do
    messages
    |> Enum.chunk_by(& &1.role)
    |> Enum.map(fn chunk ->
      role = hd(chunk).role
      parts = Enum.flat_map(chunk, & &1.parts)
      %{role: role, parts: parts}
    end)
  end

  defp format_tool(tool) when is_atom(tool) do
    %{
      name: tool.name(),
      description: tool.description(),
      parameters: format_parameters(tool.parameters())
    }
  end

  defp format_tool(%{name: name, description: desc, parameters: params}) do
    %{
      name: name,
      description: desc,
      parameters: format_parameters(params)
    }
  end

  defp format_parameters(params) when is_map(params) do
    properties =
      Enum.reduce(params, %{}, fn {name, opts}, acc ->
        prop = %{type: gemini_type(Keyword.get(opts, :type, :string))}

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
      type: "OBJECT",
      properties: properties,
      required: required
    }
  end

  defp gemini_type(:string), do: "STRING"
  defp gemini_type(:integer), do: "INTEGER"
  defp gemini_type(:number), do: "NUMBER"
  defp gemini_type(:boolean), do: "BOOLEAN"
  defp gemini_type(:array), do: "ARRAY"
  defp gemini_type(:object), do: "OBJECT"
  defp gemini_type(other), do: String.upcase(to_string(other))

  defp extract_content(parts) do
    {texts, tool_calls} =
      Enum.reduce(parts, {[], []}, fn part, {texts, tools} ->
        cond do
          part["text"] ->
            {texts ++ [part["text"]], tools}

          part["functionCall"] ->
            fc = part["functionCall"]

            tool_call =
              ToolCall.new(
                fc["name"],
                fc["name"],
                fc["args"] || %{}
              )

            {texts, tools ++ [tool_call]}

          true ->
            {texts, tools}
        end
      end)

    text_content = Enum.join(texts, "")
    tool_calls = if tool_calls == [], do: nil, else: tool_calls

    {if(text_content == "", do: nil, else: text_content), tool_calls}
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  defp maybe_add_tools(map, []), do: map

  defp maybe_add_tools(map, tools) do
    Map.put(map, :tools, format_tools(tools))
  end

  defp parse_finish_reason(nil), do: nil
  defp parse_finish_reason("STOP"), do: :stop
  defp parse_finish_reason("MAX_TOKENS"), do: :length
  defp parse_finish_reason("SAFETY"), do: :content_filter
  defp parse_finish_reason("RECITATION"), do: :content_filter
  defp parse_finish_reason("OTHER"), do: :stop
  defp parse_finish_reason(other), do: String.to_atom(String.downcase(other))

  defp parse_error(status, body) when is_map(body) do
    message = get_in(body, ["error", "message"]) || "Unknown error"
    %{status: status, message: message, body: body}
  end

  defp parse_error(status, body) do
    %{status: status, message: "Request failed", body: body}
  end

  defp make_request(path, body, _chat) do
    base_url = Config.base_url(:gemini) || @default_base_url
    api_key = Config.api_key(:gemini)

    Req.post(
      base_url <> path,
      json: body,
      headers: [{"content-type", "application/json"}],
      params: [key: api_key],
      receive_timeout: 120_000
    )
  end

  defp make_stream_request(path, body, _chat, callback) do
    base_url = Config.base_url(:gemini) || @default_base_url
    api_key = Config.api_key(:gemini)

    accumulated = %{
      content: "",
      tool_calls: [],
      model: nil,
      input_tokens: nil,
      output_tokens: nil,
      finish_reason: nil
    }

    into_fun = fn {:data, data}, {req, resp, acc} ->
      chunks = parse_json_stream(data)

      new_acc =
        Enum.reduce(chunks, acc, fn chunk_data, current_acc ->
          case parse_chunk(chunk_data) do
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
           headers: [{"content-type", "application/json"}],
           params: [key: api_key, alt: "sse"],
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

  defp parse_json_stream(data) do
    data
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "data: "))
    |> Enum.map(&String.trim_leading(&1, "data: "))
    |> Enum.reject(&(&1 == ""))
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
