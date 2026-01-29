defmodule ElixirLLM.Chat do
  @moduledoc """
  Represents a conversation with an LLM.

  The Chat struct maintains conversation state including messages, model configuration,
  tools, and callbacks. It is immutable - all operations return a new Chat struct.

  ## Example

      chat = ElixirLLM.new()
      |> ElixirLLM.model("gpt-4o")
      |> ElixirLLM.instructions("You are a helpful assistant")
      |> ElixirLLM.temperature(0.7)

      {:ok, response, chat} = ElixirLLM.ask(chat, "Hello!")
  """

  alias ElixirLLM.MCP
  alias ElixirLLM.MCP.ToolAdapter
  alias ElixirLLM.Message

  @type callback :: (any() -> any())

  @type t :: %__MODULE__{
          model: String.t() | nil,
          provider: module() | nil,
          messages: [Message.t()],
          tools: [module() | map()],
          schema: module() | nil,
          temperature: float() | nil,
          max_tokens: non_neg_integer() | nil,
          on_tool_call: callback() | nil,
          on_tool_result: callback() | nil,
          on_chunk: callback() | nil,
          params: map(),
          # Extended thinking (Claude, DeepSeek R1)
          extended_thinking: boolean() | keyword() | false,
          # MCP servers
          mcp_servers: [MCP.t()],
          # Parallel tool execution
          parallel_tools: boolean() | non_neg_integer() | keyword(),
          tool_timeout: non_neg_integer(),
          # Resilience options
          retry: keyword() | false,
          cache: boolean(),
          rate_limit: boolean(),
          circuit_breaker: boolean()
        }

  defstruct [
    :model,
    :provider,
    :schema,
    messages: [],
    tools: [],
    temperature: nil,
    max_tokens: nil,
    on_tool_call: nil,
    on_tool_result: nil,
    on_chunk: nil,
    params: %{},
    # Extended thinking: disabled by default
    extended_thinking: false,
    # MCP servers
    mcp_servers: [],
    # Parallel tool execution: enabled by default
    parallel_tools: true,
    tool_timeout: 30_000,
    # Resilience: disabled by default, users opt-in
    retry: false,
    cache: false,
    rate_limit: false,
    circuit_breaker: false
  ]

  @doc """
  Creates a new empty chat.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @doc """
  Sets the model for the chat.
  """
  @spec model(t(), String.t()) :: t()
  def model(%__MODULE__{} = chat, model_id) when is_binary(model_id) do
    provider = ElixirLLM.Config.provider_for_model(model_id)
    %{chat | model: model_id, provider: provider}
  end

  @doc """
  Explicitly sets the provider for the chat.

  This overrides the auto-detected provider from the model name.
  Accepts either a provider atom (`:openai`, `:anthropic`, etc.) or
  a provider module directly.

  ## Examples

      chat = ElixirLLM.new()
      |> ElixirLLM.provider(:anthropic)
      |> ElixirLLM.model("claude-3-opus-20240229")

      # Use OpenRouter for any model
      chat = ElixirLLM.new()
      |> ElixirLLM.provider(:openrouter)
      |> ElixirLLM.model("anthropic/claude-3-opus")

      # With a custom provider module
      chat = ElixirLLM.new()
      |> ElixirLLM.provider(MyApp.CustomProvider)
  """
  @spec provider(t(), atom() | module()) :: t()
  def provider(%__MODULE__{} = chat, provider) when is_atom(provider) do
    provider_module = ElixirLLM.Config.get_provider_module(provider)
    %{chat | provider: provider_module}
  end

  @doc """
  Sets the temperature (creativity) for responses. Range: 0.0 to 2.0.
  """
  @spec temperature(t(), float()) :: t()
  def temperature(%__MODULE__{} = chat, temp) when is_float(temp) or is_integer(temp) do
    %{chat | temperature: temp / 1}
  end

  @doc """
  Sets the maximum tokens for the response.
  """
  @spec max_tokens(t(), non_neg_integer()) :: t()
  def max_tokens(%__MODULE__{} = chat, tokens) when is_integer(tokens) and tokens > 0 do
    %{chat | max_tokens: tokens}
  end

  @doc """
  Adds a system instruction message. Use `replace: true` to replace existing instructions.
  """
  @spec instructions(t(), String.t(), keyword()) :: t()
  def instructions(%__MODULE__{} = chat, content, opts \\ []) do
    if Keyword.get(opts, :replace, false) do
      messages = Enum.reject(chat.messages, &(&1.role == :system))
      %{chat | messages: [Message.system(content) | messages]}
    else
      add_message(chat, Message.system(content))
    end
  end

  @doc """
  Registers a tool with the chat. Accepts a module implementing the Tool behaviour
  or an inline tool map.
  """
  @spec tool(t(), module() | map()) :: t()
  def tool(%__MODULE__{} = chat, tool) do
    %{chat | tools: chat.tools ++ [tool]}
  end

  @doc """
  Registers multiple tools at once. Use `replace: true` to clear existing tools first.
  """
  @spec tools(t(), [module() | map()], keyword()) :: t()
  def tools(%__MODULE__{} = chat, tool_list, opts \\ []) do
    if Keyword.get(opts, :replace, false) do
      %{chat | tools: tool_list}
    else
      %{chat | tools: chat.tools ++ tool_list}
    end
  end

  @doc """
  Sets a callback for when a tool is called.
  """
  @spec on_tool_call(t(), callback()) :: t()
  def on_tool_call(%__MODULE__{} = chat, callback) when is_function(callback, 1) do
    %{chat | on_tool_call: callback}
  end

  @doc """
  Sets a callback for when a tool returns a result.
  """
  @spec on_tool_result(t(), callback()) :: t()
  def on_tool_result(%__MODULE__{} = chat, callback) when is_function(callback, 1) do
    %{chat | on_tool_result: callback}
  end

  @doc """
  Sets additional provider-specific parameters.
  """
  @spec params(t(), map()) :: t()
  def params(%__MODULE__{} = chat, params) when is_map(params) do
    %{chat | params: Map.merge(chat.params, params)}
  end

  @doc """
  Sets a schema for structured output. The response will be parsed into the schema struct.
  """
  @spec schema(t(), module()) :: t()
  def schema(%__MODULE__{} = chat, schema_module) when is_atom(schema_module) do
    %{chat | schema: schema_module}
  end

  @doc """
  Attaches an MCP server to the chat.

  The server's tools will be automatically added to the chat's tool list.
  Multiple MCP servers can be attached to a single chat.

  ## Examples

      {:ok, conn} = ElixirLLM.MCP.connect("npx", ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"])

      {:ok, response, _} =
        ElixirLLM.new()
        |> ElixirLLM.model("claude-sonnet-4-20250514")
        |> ElixirLLM.mcp_server(conn)
        |> ElixirLLM.ask("List files in /tmp")
  """
  @spec mcp_server(t(), MCP.t()) :: t()
  def mcp_server(%__MODULE__{} = chat, %MCP{} = server) do
    mcp_tools = ToolAdapter.to_elixir_llm_tools(server)
    %{chat | mcp_servers: chat.mcp_servers ++ [server], tools: chat.tools ++ mcp_tools}
  end

  # ===========================================================================
  # Parallel Tool Execution Options
  # ===========================================================================

  @doc """
  Configures parallel tool execution.

  By default, ElixirLLM executes tools in parallel using `Task.Supervisor.async_stream_nolink`.
  This can significantly speed up tool execution when multiple tools are called at once.

  ## Options

    * `true` - Enable parallel execution with `max_concurrency: System.schedulers_online()` (default)
    * `false` - Disable parallel execution (sequential, backwards compatible)
    * integer - Set max concurrent tasks (e.g., `4`)
    * keyword list - Full configuration:
      * `:max_concurrency` - Maximum concurrent tasks (default: `System.schedulers_online()`)
      * `:timeout` - Timeout per tool in ms (default: chat's `tool_timeout`)
      * `:ordered` - Preserve result order (default: `true`)

  ## Examples

      # Disable parallel execution
      chat |> ElixirLLM.parallel_tools(false)

      # Limit to 4 concurrent tools
      chat |> ElixirLLM.parallel_tools(4)

      # Full configuration
      chat |> ElixirLLM.parallel_tools(max_concurrency: 8, timeout: 60_000, ordered: true)
  """
  @spec parallel_tools(t(), boolean() | non_neg_integer() | keyword()) :: t()
  def parallel_tools(%__MODULE__{} = chat, opts \\ true) do
    %{chat | parallel_tools: opts}
  end

  @doc """
  Sets the timeout for individual tool execution in milliseconds.

  When a tool exceeds this timeout during parallel execution, it will be killed
  and return `{:error, :tool_timeout}`. Other tools continue execution.

  ## Examples

      # Set 2 minute timeout
      chat |> ElixirLLM.tool_timeout(120_000)
  """
  @spec tool_timeout(t(), non_neg_integer()) :: t()
  def tool_timeout(%__MODULE__{} = chat, timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0 do
    %{chat | tool_timeout: timeout_ms}
  end

  @doc """
  Enables extended thinking (chain-of-thought) for supported models.

  When enabled, the model will show its reasoning process before the final answer.
  The thinking content is returned in `response.thinking`.

  ## Supported Models

    * Claude Sonnet 4, Claude Opus 4 (Anthropic)
    * DeepSeek Reasoner (R1)
    * Gemini 2.5 Flash (with reasoning enabled)

  ## Options

    * `:budget_tokens` - Maximum tokens for thinking (default: 10000, Anthropic only)

  ## Examples

      # Simple enable
      chat
      |> ElixirLLM.extended_thinking()
      |> ElixirLLM.ask("Solve this math problem: ...")

      # With budget
      chat
      |> ElixirLLM.extended_thinking(budget_tokens: 20000)
      |> ElixirLLM.ask("Complex reasoning task...")

      # Access thinking in response
      {:ok, response, _} = ElixirLLM.ask(chat, "...")
      IO.puts("Thinking: " <> response.thinking)
      IO.puts("Answer: " <> response.content)
  """
  @spec extended_thinking(t(), boolean() | keyword()) :: t()
  def extended_thinking(%__MODULE__{} = chat, opts \\ true) do
    %{chat | extended_thinking: opts}
  end

  # ===========================================================================
  # Resilience Options
  # ===========================================================================

  @doc """
  Enables automatic retry with exponential backoff.

  ## Options

    * `:max_attempts` - Maximum retry attempts (default: 3)
    * `:base_delay_ms` - Initial delay between retries (default: 1000)
    * `:max_delay_ms` - Maximum delay between retries (default: 30000)
    * `:jitter` - Add random jitter to delays (default: true)
    * `:on_retry` - Callback `(attempt, error) -> any()` called before each retry

  ## Examples

      chat
      |> ElixirLLM.with_retry()
      |> ElixirLLM.ask("Hello!")

      chat
      |> ElixirLLM.with_retry(max_attempts: 5, base_delay_ms: 500)
      |> ElixirLLM.ask("Hello!")
  """
  @spec with_retry(t(), keyword()) :: t()
  def with_retry(%__MODULE__{} = chat, opts \\ []) do
    %{chat | retry: opts}
  end

  @doc """
  Enables response caching.

  Caches responses based on model, messages, and settings to reduce API costs.
  Cache configuration (TTL, max entries) is set in application config.

  ## Example

      chat
      |> ElixirLLM.with_cache()
      |> ElixirLLM.ask("What is 2+2?")  # First call hits API
      |> ElixirLLM.ask("What is 2+2?")  # Second call returns cached response
  """
  @spec with_cache(t()) :: t()
  def with_cache(%__MODULE__{} = chat) do
    %{chat | cache: true}
  end

  @doc """
  Enables client-side rate limiting.

  Automatically acquires tokens before making requests to prevent hitting
  provider rate limits. Rate limits are configured per provider in application config.

  ## Example

      chat
      |> ElixirLLM.with_rate_limiting()
      |> ElixirLLM.ask("Hello!")
  """
  @spec with_rate_limiting(t()) :: t()
  def with_rate_limiting(%__MODULE__{} = chat) do
    %{chat | rate_limit: true}
  end

  @doc """
  Enables circuit breaker protection.

  Prevents cascading failures by temporarily blocking requests to failing providers.
  Configuration (failure threshold, recovery timeout) is set in application config.

  ## Example

      chat
      |> ElixirLLM.with_circuit_breaker()
      |> ElixirLLM.ask("Hello!")
  """
  @spec with_circuit_breaker(t()) :: t()
  def with_circuit_breaker(%__MODULE__{} = chat) do
    %{chat | circuit_breaker: true}
  end

  @doc """
  Adds a message to the chat history.
  """
  @spec add_message(t(), Message.t()) :: t()
  def add_message(%__MODULE__{} = chat, %Message{} = message) do
    %{chat | messages: chat.messages ++ [message]}
  end

  @doc """
  Adds multiple messages to the chat history.
  """
  @spec add_messages(t(), [Message.t()]) :: t()
  def add_messages(%__MODULE__{} = chat, messages) when is_list(messages) do
    %{chat | messages: chat.messages ++ messages}
  end
end
