defmodule ElixirLLM.Response do
  @moduledoc """
  Represents a complete response from an LLM provider.

  Contains the assistant's message along with usage statistics and metadata.
  """

  @type t :: %__MODULE__{
          content: String.t() | nil,
          tool_calls: [ElixirLLM.ToolCall.t()] | nil,
          model: String.t(),
          input_tokens: non_neg_integer() | nil,
          output_tokens: non_neg_integer() | nil,
          total_tokens: non_neg_integer() | nil,
          finish_reason: atom() | nil
        }

  defstruct [
    :content,
    :tool_calls,
    :model,
    :input_tokens,
    :output_tokens,
    :total_tokens,
    :finish_reason
  ]

  @doc """
  Creates a new response from provider data.
  """
  @spec new(keyword()) :: t()
  def new(attrs) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Returns true if the response contains tool calls.
  """
  @spec has_tool_calls?(t()) :: boolean()
  def has_tool_calls?(%__MODULE__{tool_calls: nil}), do: false
  def has_tool_calls?(%__MODULE__{tool_calls: []}), do: false
  def has_tool_calls?(%__MODULE__{tool_calls: _}), do: true
end
