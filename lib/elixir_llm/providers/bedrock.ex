defmodule ElixirLLM.Providers.Bedrock do
  @moduledoc """
  AWS Bedrock provider implementation.

  Supports Claude, Llama, Mistral, and other models through AWS Bedrock using
  the Converse API with SigV4 request signing.

  ## Configuration

      config :elixir_llm,
        bedrock: [
          access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
          secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
          region: System.get_env("AWS_REGION") || "us-east-1",
          timeout: 120_000  # optional
        ]

  ## Model Names

  Use the `bedrock/` prefix with model names:

      ElixirLLM.new()
      |> ElixirLLM.model("bedrock/claude-sonnet-4")
      |> ElixirLLM.ask("Hello!")

  Or use full Bedrock model IDs:

      ElixirLLM.new()
      |> ElixirLLM.provider(:bedrock)
      |> ElixirLLM.model("anthropic.claude-sonnet-4-20250514-v1:0")

  ## Supported Models

  Claude models:
    * `bedrock/claude-sonnet-4` - Claude Sonnet 4
    * `bedrock/claude-3-5-sonnet` - Claude 3.5 Sonnet
    * `bedrock/claude-3-opus` - Claude 3 Opus
    * `bedrock/claude-3-haiku` - Claude 3 Haiku

  Llama models:
    * `bedrock/llama-3-70b` - Llama 3 70B Instruct
    * `bedrock/llama-3-8b` - Llama 3 8B Instruct

  Mistral models:
    * `bedrock/mistral-large` - Mistral Large
    * `bedrock/mistral-small` - Mistral Small
  """

  @behaviour ElixirLLM.Provider

  alias ElixirLLM.{Chat, Chunk, Config, Response, Telemetry, ToolCall}
  alias ElixirLLM.Error.Helpers, as: ErrorHelpers
  alias ElixirLLM.Providers.Base

  @provider :bedrock
  @service "bedrock"

  # Model ID mappings (friendly name -> Bedrock model ID)
  @model_mappings %{
    # Claude models
    "bedrock/claude-sonnet-4" => "anthropic.claude-sonnet-4-20250514-v1:0",
    "bedrock/claude-opus-4" => "anthropic.claude-opus-4-20250514-v1:0",
    "bedrock/claude-3-5-sonnet" => "anthropic.claude-3-5-sonnet-20241022-v2:0",
    "bedrock/claude-3-opus" => "anthropic.claude-3-opus-20240229-v1:0",
    "bedrock/claude-3-sonnet" => "anthropic.claude-3-sonnet-20240229-v1:0",
    "bedrock/claude-3-haiku" => "anthropic.claude-3-haiku-20240307-v1:0",
    # Llama models
    "bedrock/llama-3-70b" => "meta.llama3-70b-instruct-v1:0",
    "bedrock/llama-3-8b" => "meta.llama3-8b-instruct-v1:0",
    "bedrock/llama-3-1-405b" => "meta.llama3-1-405b-instruct-v1:0",
    "bedrock/llama-3-1-70b" => "meta.llama3-1-70b-instruct-v1:0",
    # Mistral models
    "bedrock/mistral-large" => "mistral.mistral-large-2402-v1:0",
    "bedrock/mistral-small" => "mistral.mistral-small-2402-v1:0",
    "bedrock/mixtral-8x7b" => "mistral.mixtral-8x7b-instruct-v0:1"
  }

  @impl true
  def chat(%Chat{} = chat) do
    metadata = %{provider: @provider, model: chat.model}

    Telemetry.span(:chat, metadata, fn ->
      body = build_request_body(chat)
      model_id = resolve_model_id(chat.model)

      case make_request(model_id, body) do
        {:ok, %{status: 200, body: response_body}} ->
          response = parse_response(response_body, chat.model)
          Telemetry.emit(:chat_complete, %{tokens: response.total_tokens}, metadata)
          {:ok, response}

        {:ok, %{status: status, body: body}} ->
          error = parse_bedrock_error(status, body)
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
    body = build_request_body(chat)
    model_id = resolve_model_id(chat.model)

    Telemetry.span(:stream, metadata, fn ->
      case make_stream_request(model_id, body, callback, chat.model) do
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
    # Bedrock Converse API tool format - returns list of toolSpec wrappers
    Enum.map(tools, fn tool ->
      %{
        toolSpec: format_tool(tool)
      }
    end)
  end

  @impl true
  def parse_response(body, model \\ nil) do
    output = body["output"] || %{}
    message = output["message"] || %{}
    usage = body["usage"] || %{}
    content_blocks = message["content"] || []

    {text_content, tool_calls} = extract_content(content_blocks)

    Response.new(
      content: text_content,
      tool_calls: tool_calls,
      model: model,
      input_tokens: usage["inputTokens"],
      output_tokens: usage["outputTokens"],
      total_tokens: (usage["inputTokens"] || 0) + (usage["outputTokens"] || 0),
      finish_reason: parse_stop_reason(body["stopReason"])
    )
  end

  @impl true
  def parse_chunk(event_data) do
    case event_data do
      %{"contentBlockDelta" => %{"delta" => delta}} ->
        parse_delta(delta)

      %{"messageStart" => %{"role" => _role}} ->
        nil

      %{"messageStop" => %{"stopReason" => reason}} ->
        Chunk.new(finish_reason: parse_stop_reason(reason))

      %{"metadata" => %{"usage" => usage}} ->
        Chunk.new(
          input_tokens: usage["inputTokens"],
          output_tokens: usage["outputTokens"]
        )

      _ ->
        nil
    end
  end

  # Private functions

  defp build_request_body(%Chat{} = chat) do
    {system_messages, other_messages} =
      Enum.split_with(chat.messages, &(&1.role == :system))

    body = %{
      messages: format_messages(other_messages)
    }

    body =
      if system_messages != [] do
        system_content = Enum.map(system_messages, fn msg -> %{text: msg.content} end)
        Map.put(body, :system, system_content)
      else
        body
      end

    # Build inference config
    inference_config = %{}

    inference_config =
      if chat.max_tokens do
        Map.put(inference_config, :maxTokens, chat.max_tokens)
      else
        Map.put(inference_config, :maxTokens, 4096)
      end

    inference_config =
      if chat.temperature do
        Map.put(inference_config, :temperature, chat.temperature)
      else
        inference_config
      end

    body = Map.put(body, :inferenceConfig, inference_config)

    # Add tools if present
    body = maybe_add_tools(body, chat.tools)

    # Merge any additional params
    Map.merge(body, chat.params)
  end

  defp format_messages(messages) do
    Enum.map(messages, &format_message/1)
  end

  defp format_message(%{role: :user, content: content}) when is_binary(content) do
    %{role: "user", content: [%{text: content}]}
  end

  defp format_message(%{role: :assistant, content: content, tool_calls: nil})
       when is_binary(content) do
    %{role: "assistant", content: [%{text: content}]}
  end

  defp format_message(%{role: :assistant, content: nil, tool_calls: nil}) do
    %{role: "assistant", content: [%{text: ""}]}
  end

  defp format_message(%{role: :assistant, content: content, tool_calls: tool_calls}) do
    content_blocks = []

    content_blocks =
      if content && content != "" do
        content_blocks ++ [%{text: content}]
      else
        content_blocks
      end

    content_blocks =
      if tool_calls != nil and tool_calls != [] do
        tool_use_blocks =
          Enum.map(tool_calls, fn tc ->
            %{
              toolUse: %{
                toolUseId: tc.id,
                name: tc.name,
                input: tc.arguments
              }
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
          toolResult: %{
            toolUseId: tool_call_id,
            content: [%{text: content}]
          }
        }
      ]
    }
  end

  defp format_tool(tool) when is_atom(tool) do
    %{
      name: tool.name(),
      description: tool.description(),
      inputSchema: %{
        json: Base.format_parameters(tool.parameters())
      }
    }
  end

  defp format_tool(%{name: name, description: desc, parameters: params}) do
    %{
      name: name,
      description: desc,
      inputSchema: %{
        json: Base.format_parameters(params)
      }
    }
  end

  defp extract_content(content_blocks) do
    {texts, tool_uses} =
      Enum.reduce(content_blocks, {[], []}, fn block, {texts, tools} ->
        cond do
          Map.has_key?(block, "text") ->
            {texts ++ [block["text"]], tools}

          Map.has_key?(block, "toolUse") ->
            tool_use = block["toolUse"]

            tool_call =
              ToolCall.new(
                tool_use["toolUseId"],
                tool_use["name"],
                tool_use["input"] || %{}
              )

            {texts, tools ++ [tool_call]}

          true ->
            {texts, tools}
        end
      end)

    text_content = Enum.join(texts, "")
    tool_calls = if tool_uses == [], do: nil, else: tool_uses

    {if(text_content == "", do: nil, else: text_content), tool_calls}
  end

  defp parse_delta(%{"text" => text}) do
    Chunk.new(content: text)
  end

  defp parse_delta(_), do: nil

  defp maybe_add_tools(body, []), do: body

  defp maybe_add_tools(body, tools) do
    tool_config = %{tools: format_tools(tools)}
    Map.put(body, :toolConfig, tool_config)
  end

  defp parse_stop_reason(nil), do: nil
  defp parse_stop_reason("end_turn"), do: :stop
  defp parse_stop_reason("stop_sequence"), do: :stop
  defp parse_stop_reason("max_tokens"), do: :length
  defp parse_stop_reason("tool_use"), do: :tool_calls
  defp parse_stop_reason(other) when is_binary(other), do: String.to_atom(other)
  defp parse_stop_reason(_), do: nil

  defp resolve_model_id(model) do
    # Check if it's a friendly name with mapping
    case Map.get(@model_mappings, model) do
      nil ->
        # Strip bedrock/ prefix if present, otherwise use as-is
        model
        |> String.replace_prefix("bedrock/", "")

      bedrock_id ->
        bedrock_id
    end
  end

  defp make_request(model_id, body) do
    {url, headers} = build_signed_request(model_id, body, "converse")

    Req.post(
      url,
      json: body,
      headers: headers,
      receive_timeout: Base.get_timeout(@provider)
    )
  end

  defp make_stream_request(model_id, body, callback, model) do
    {url, headers} = build_signed_request(model_id, body, "converse-stream")

    # Initialize accumulator in process dictionary
    Base.init_stream_accumulator()

    into_fun = fn {:data, data}, {req, resp} ->
      # Bedrock streaming uses AWS event stream format
      events = parse_event_stream(data)
      Enum.each(events, &process_stream_event(&1, callback))
      {:cont, {req, resp}}
    end

    case Req.post(
           url,
           json: body,
           headers: headers,
           receive_timeout: Base.get_timeout(@provider),
           into: into_fun
         ) do
      {:ok, %{status: 200}} ->
        final_acc = Base.get_stream_accumulator()
        response = Base.build_final_response(final_acc)
        {:ok, %{response | model: model}}

      {:ok, %{status: status, body: error_body}} ->
        Base.get_stream_accumulator()
        {:error, parse_bedrock_error(status, error_body)}

      {:error, reason} ->
        Base.get_stream_accumulator()
        {:error, ErrorHelpers.from_transport_error(reason, @provider)}
    end
  end

  defp build_signed_request(model_id, body, action) do
    config = Config.provider_config(@provider)
    region = config[:region] || System.get_env("AWS_REGION") || "us-east-1"
    access_key_id = config[:access_key_id] || System.get_env("AWS_ACCESS_KEY_ID")
    secret_access_key = config[:secret_access_key] || System.get_env("AWS_SECRET_ACCESS_KEY")

    if is_nil(access_key_id) or is_nil(secret_access_key) do
      raise ArgumentError, """
      AWS credentials not configured for Bedrock.

      Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables, or configure in config.exs:

          config :elixir_llm,
            bedrock: [
              access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
              secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
              region: System.get_env("AWS_REGION")
            ]
      """
    end

    host = "bedrock-runtime.#{region}.amazonaws.com"
    path = "/model/#{URI.encode(model_id)}/#{action}"
    url = "https://#{host}#{path}"

    body_json = Jason.encode!(body)
    datetime = :calendar.universal_time()

    headers =
      :aws_signature.sign_v4(
        access_key_id,
        secret_access_key,
        region,
        @service,
        datetime,
        "POST",
        url,
        [{"host", host}, {"content-type", "application/json"}],
        body_json,
        []
      )

    # Convert headers to list of tuples format Req expects
    header_list = Enum.map(headers, fn {k, v} -> {k, v} end)

    {url, header_list}
  end

  defp parse_event_stream(data) do
    # AWS event stream format is binary with headers
    # For simplicity, we try to extract JSON payloads
    # Real implementation would parse the binary event stream format

    # Try to find JSON objects in the data
    data
    |> String.split(~r/\{/, trim: true)
    |> Enum.map(fn part ->
      json_str = "{" <> part

      case Jason.decode(json_str) do
        {:ok, decoded} -> decoded
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
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

  defp parse_bedrock_error(status, body) when is_map(body) do
    # Bedrock uses different error message fields
    body =
      if body["message"] || body["error"] do
        body
      else
        Map.put(body, "error", %{"message" => body["Message"] || "Unknown error"})
      end

    Base.parse_error(status, body, @provider)
  end

  defp parse_bedrock_error(status, body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_bedrock_error(status, decoded)
      _ -> Base.parse_error(status, %{"error" => %{"message" => body}}, @provider)
    end
  end

  defp parse_bedrock_error(status, _) do
    Base.parse_error(status, %{"error" => %{"message" => "Unknown error"}}, @provider)
  end
end
