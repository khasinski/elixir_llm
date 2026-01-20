defmodule ElixirLLM do
  @moduledoc """
  A unified Elixir API for LLMs.

  ElixirLLM provides one beautiful interface for OpenAI, Anthropic, Ollama, and more.
  Inspired by RubyLLM.

  ## Quick Start

      # Simple chat
      {:ok, response} = ElixirLLM.chat("What is Elixir?")

      # With configuration
      {:ok, response, chat} =
        ElixirLLM.new()
        |> ElixirLLM.model("claude-sonnet-4-5")
        |> ElixirLLM.temperature(0.7)
        |> ElixirLLM.ask("Explain OTP in simple terms")

      # With streaming
      ElixirLLM.new()
      |> ElixirLLM.model("gpt-4o")
      |> ElixirLLM.ask("Write a haiku", stream: fn chunk ->
        IO.write(chunk.content || "")
      end)

  ## Tools

      defmodule MyApp.Tools.Calculator do
        use ElixirLLM.Tool

        @impl true
        def name, do: "calculator"

        @impl true
        def description, do: "Performs basic math calculations"

        @impl true
        def parameters do
          %{
            expression: [type: :string, description: "Math expression to evaluate"]
          }
        end

        @impl true
        def execute(%{expression: expr}) do
          # Safe evaluation...
          {:ok, 42}
        end
      end

      {:ok, response, chat} =
        ElixirLLM.new()
        |> ElixirLLM.tool(MyApp.Tools.Calculator)
        |> ElixirLLM.ask("What is 6 * 7?")

  ## Configuration

  Configure API keys in your `config/config.exs`:

      config :elixir_llm,
        default_model: "gpt-4o",

        openai: [
          api_key: System.get_env("OPENAI_API_KEY")
        ],

        anthropic: [
          api_key: System.get_env("ANTHROPIC_API_KEY")
        ],

        ollama: [
          base_url: "http://localhost:11434"
        ]
  """

  alias ElixirLLM.{Chat, Message, Response, Telemetry, Tool}

  # Re-export Chat functions for pipe-friendly API
  defdelegate model(chat, model_id), to: Chat
  defdelegate temperature(chat, temp), to: Chat
  defdelegate max_tokens(chat, tokens), to: Chat
  defdelegate instructions(chat, content, opts \\ []), to: Chat
  defdelegate tool(chat, tool), to: Chat
  defdelegate tools(chat, tools, opts \\ []), to: Chat
  defdelegate schema(chat, schema_module), to: Chat
  defdelegate on_tool_call(chat, callback), to: Chat
  defdelegate on_tool_result(chat, callback), to: Chat
  defdelegate params(chat, params), to: Chat

  @doc """
  Creates a new chat instance.

  ## Options

    * `:model` - The model to use (e.g., "gpt-4o", "claude-sonnet-4-5")

  ## Examples

      chat = ElixirLLM.new()
      chat = ElixirLLM.new(model: "claude-sonnet-4-5")
  """
  @spec new(keyword()) :: Chat.t()
  def new(opts \\ []) do
    chat = Chat.new()

    case Keyword.get(opts, :model) do
      nil -> chat
      model_id -> Chat.model(chat, model_id)
    end
  end

  @doc """
  Simple one-shot chat completion.

  ## Examples

      {:ok, response} = ElixirLLM.chat("What is Elixir?")
      {:ok, response} = ElixirLLM.chat("Explain OTP", model: "claude-sonnet-4-5")
  """
  @spec chat(String.t(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  def chat(message, opts \\ []) do
    new(opts)
    |> Chat.add_message(Message.user(message))
    |> do_ask([])
  end

  @doc """
  Sends a message and returns the assistant's response.

  Maintains conversation history in the returned chat.

  ## Options

    * `:stream` - A callback function `(Chunk.t() -> any())` for streaming responses
    * `:with` - File path(s) to include with the message (not yet implemented)

  ## Examples

      # Simple ask
      {:ok, response, chat} = ElixirLLM.ask(chat, "Hello!")

      # Continue the conversation
      {:ok, response, chat} = ElixirLLM.ask(chat, "Tell me more")

      # With streaming
      {:ok, response, chat} = ElixirLLM.ask(chat, "Write a story", stream: fn chunk ->
        IO.write(chunk.content || "")
      end)
  """
  @spec ask(Chat.t(), String.t(), keyword()) ::
          {:ok, Response.t(), Chat.t()} | {:error, term()}
  def ask(%Chat{} = chat, message, opts \\ []) do
    chat = Chat.add_message(chat, Message.user(message))

    case do_ask(chat, opts) do
      {:ok, response} ->
        # Add assistant message to history
        assistant_message = Message.assistant(response.content, tool_calls: response.tool_calls)
        chat = Chat.add_message(chat, assistant_message)
        {:ok, response, chat}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns a stream of chunks for the given message.

  ## Examples

      ElixirLLM.new()
      |> ElixirLLM.model("gpt-4o")
      |> ElixirLLM.stream("Write a poem")
      |> Stream.each(fn chunk -> IO.write(chunk.content || "") end)
      |> Stream.run()
  """
  @spec stream(Chat.t(), String.t()) :: Enumerable.t()
  def stream(%Chat{} = chat, message) do
    chat = Chat.add_message(chat, Message.user(message))
    provider = get_provider(chat)

    Stream.resource(
      fn -> {chat, provider, nil} end,
      fn
        {chat, provider, nil} ->
          # Start streaming and collect chunks
          {:ok, _response} =
            provider.stream(chat, fn chunk ->
              send(self(), {:chunk, chunk})
            end)

          receive_chunks([])

        :done ->
          {:halt, :done}
      end,
      fn _ -> :ok end
    )
  end

  defp receive_chunks(acc) do
    receive do
      {:chunk, chunk} ->
        {[chunk], receive_chunks(acc)}
    after
      0 ->
        {:halt, :done}
    end
  end

  # Private implementation

  defp do_ask(%Chat{} = chat, opts) do
    provider = get_provider(chat)

    case Keyword.get(opts, :stream) do
      nil ->
        # Non-streaming request
        case provider.chat(chat) do
          {:ok, response} ->
            # Handle tool calls if present
            handle_tool_calls(chat, response, provider)

          error ->
            error
        end

      callback when is_function(callback, 1) ->
        # Streaming request
        case provider.stream(chat, callback) do
          {:ok, response} ->
            # Handle tool calls if present
            handle_tool_calls(chat, response, provider)

          error ->
            error
        end
    end
  end

  defp get_provider(%Chat{provider: nil, model: nil}) do
    ElixirLLM.Config.default_provider()
  end

  defp get_provider(%Chat{provider: nil, model: model}) do
    ElixirLLM.Config.provider_for_model(model)
  end

  defp get_provider(%Chat{provider: provider}) do
    provider
  end

  defp handle_tool_calls(chat, response, provider) do
    if Response.has_tool_calls?(response) do
      execute_tool_loop(chat, response, provider)
    else
      {:ok, response}
    end
  end

  defp execute_tool_loop(chat, response, provider, depth \\ 0) do
    # Prevent infinite loops
    if depth > 10 do
      {:error, :max_tool_depth_exceeded}
    else
      # Add assistant message with tool calls
      assistant_msg = Message.assistant(response.content, tool_calls: response.tool_calls)
      chat = Chat.add_message(chat, assistant_msg)

      # Execute each tool call
      tool_results =
        Enum.map(response.tool_calls, fn tool_call ->
          execute_tool_call(chat, tool_call)
        end)

      # Add tool results to chat
      chat =
        Enum.reduce(tool_results, chat, fn {tool_call_id, result}, acc ->
          result_content =
            case result do
              {:ok, value} -> encode_result(value)
              {:error, reason} -> "Error: #{inspect(reason)}"
            end

          Chat.add_message(acc, Message.tool_result(tool_call_id, result_content))
        end)

      # Continue the conversation
      case provider.chat(chat) do
        {:ok, new_response} ->
          if Response.has_tool_calls?(new_response) do
            execute_tool_loop(chat, new_response, provider, depth + 1)
          else
            {:ok, new_response}
          end

        error ->
          error
      end
    end
  end

  defp execute_tool_call(chat, tool_call) do
    start_time = System.monotonic_time()

    # Emit tool call telemetry
    Telemetry.tool_call(tool_call.name, tool_call.arguments)

    # Invoke callback if set
    if chat.on_tool_call, do: chat.on_tool_call.(tool_call)

    # Find the tool
    tool = find_tool(chat.tools, tool_call.name)

    result =
      if tool do
        Tool.execute(tool, tool_call.arguments)
      else
        {:error, "Unknown tool: #{tool_call.name}"}
      end

    # Emit tool result telemetry
    duration = System.monotonic_time() - start_time
    Telemetry.tool_result(tool_call.name, result, duration)

    # Invoke callback if set
    if chat.on_tool_result, do: chat.on_tool_result.(result)

    {tool_call.id, result}
  end

  defp find_tool(tools, name) do
    Enum.find(tools, fn tool ->
      Tool.get_name(tool) == name
    end)
  end

  defp encode_result(value) when is_binary(value), do: value
  defp encode_result(value) when is_map(value), do: Jason.encode!(value)
  defp encode_result(value) when is_list(value), do: Jason.encode!(value)
  defp encode_result(value), do: inspect(value)

  # ============================================================================
  # Embeddings
  # ============================================================================

  @doc """
  Generates embeddings for the given text(s).

  ## Options

    * `:model` - The embedding model to use (default: "text-embedding-3-small")
    * `:dimensions` - Number of dimensions (for models that support it)

  ## Examples

      {:ok, embedding} = ElixirLLM.embed("Hello, world!")
      {:ok, embeddings} = ElixirLLM.embed(["Hello", "World"])
  """
  defdelegate embed(input, opts \\ []), to: ElixirLLM.Embedding, as: :create

  # ============================================================================
  # Content helpers
  # ============================================================================

  @doc """
  Creates an image content for multi-modal messages.

  ## Examples

      content = ElixirLLM.image("photo.jpg")
      {:ok, response, chat} = ElixirLLM.ask(chat, "What's in this image?", with: content)
  """
  defdelegate image(path), to: ElixirLLM.Content

  @doc "Creates image content from a URL."
  defdelegate image_url(url), to: ElixirLLM.Content

  @doc "Creates image content from base64 data."
  defdelegate image_base64(data, media_type \\ "image/png"), to: ElixirLLM.Content

  @doc "Creates audio content from a file path."
  defdelegate audio(path), to: ElixirLLM.Content

  @doc "Creates PDF content from a file path."
  defdelegate pdf(path), to: ElixirLLM.Content
end
