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
          params: map()
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
    params: %{}
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
