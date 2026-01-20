defmodule ElixirLLM.ToolCall do
  @moduledoc """
  Represents a tool call requested by the model.

  Contains the tool name, arguments, and a unique ID for matching with results.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          arguments: map()
        }

  @enforce_keys [:id, :name, :arguments]
  defstruct [:id, :name, :arguments]

  @doc """
  Creates a new tool call.
  """
  @spec new(String.t(), String.t(), map()) :: t()
  def new(id, name, arguments) do
    %__MODULE__{
      id: id,
      name: name,
      arguments: arguments
    }
  end
end
