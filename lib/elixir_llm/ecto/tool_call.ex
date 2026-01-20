defmodule ElixirLLM.Ecto.ToolCall do
  @moduledoc """
  Ecto integration for persisted tool calls.

      defmodule MyApp.LLM.ToolCall do
        use Ecto.Schema
        use ElixirLLM.Ecto.ToolCall

        schema "llm_tool_calls" do
          field :call_id, :string
          field :tool_name, :string
          field :arguments, :map
          field :result, :string

          belongs_to :message, MyApp.LLM.Message

          timestamps()
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      @doc """
      Converts this tool call to an ElixirLLM.ToolCall struct.
      """
      def to_elixir_llm(tc) do
        ElixirLLM.Ecto.ToolCall.do_to_elixir_llm(tc)
      end
    end
  end

  @doc false
  def do_to_elixir_llm(tc) do
    ElixirLLM.ToolCall.new(tc.call_id, tc.tool_name, tc.arguments || %{})
  end
end
