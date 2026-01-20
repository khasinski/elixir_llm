defmodule ElixirLLM.Chunk do
  @moduledoc """
  Represents a streaming chunk from an LLM provider.

  Chunks are yielded during streaming responses and contain partial content
  or tool call information.
  """

  @type t :: %__MODULE__{
          content: String.t() | nil,
          tool_calls: [ElixirLLM.ToolCall.t()] | nil,
          model: String.t() | nil,
          input_tokens: non_neg_integer() | nil,
          output_tokens: non_neg_integer() | nil,
          finish_reason: atom() | nil
        }

  defstruct [
    :content,
    :tool_calls,
    :model,
    :input_tokens,
    :output_tokens,
    :finish_reason
  ]

  @doc """
  Creates a new chunk from provider data.
  """
  @spec new(keyword()) :: t()
  def new(attrs) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Returns true if this is the final chunk (has a finish reason).
  """
  @spec final?(t()) :: boolean()
  def final?(%__MODULE__{finish_reason: nil}), do: false
  def final?(%__MODULE__{finish_reason: _}), do: true
end
