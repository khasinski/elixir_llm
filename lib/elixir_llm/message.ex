defmodule ElixirLLM.Message do
  @moduledoc """
  Represents a message in a conversation.

  Messages have a role (`:user`, `:assistant`, `:system`, or `:tool`) and content.
  They may also contain tool calls (for assistant messages) or tool results.
  """

  @type role :: :user | :assistant | :system | :tool

  @type t :: %__MODULE__{
          role: role(),
          content: String.t() | nil,
          tool_calls: [ElixirLLM.ToolCall.t()] | nil,
          tool_call_id: String.t() | nil,
          name: String.t() | nil
        }

  @enforce_keys [:role]
  defstruct [
    :role,
    :content,
    :tool_calls,
    :tool_call_id,
    :name
  ]

  @doc """
  Creates a new user message.
  """
  @spec user(String.t()) :: t()
  def user(content) do
    %__MODULE__{role: :user, content: content}
  end

  @doc """
  Creates a new assistant message.
  """
  @spec assistant(String.t(), keyword()) :: t()
  def assistant(content, opts \\ []) do
    %__MODULE__{
      role: :assistant,
      content: content,
      tool_calls: Keyword.get(opts, :tool_calls)
    }
  end

  @doc """
  Creates a new system message.
  """
  @spec system(String.t()) :: t()
  def system(content) do
    %__MODULE__{role: :system, content: content}
  end

  @doc """
  Creates a new tool result message.
  """
  @spec tool_result(String.t(), String.t()) :: t()
  def tool_result(tool_call_id, content) do
    %__MODULE__{
      role: :tool,
      content: content,
      tool_call_id: tool_call_id
    }
  end
end
