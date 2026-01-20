defmodule ElixirLLM.Ecto.Message do
  @moduledoc """
  Ecto integration for persisted messages.

      defmodule MyApp.LLM.Message do
        use Ecto.Schema
        use ElixirLLM.Ecto.Message

        schema "llm_messages" do
          field :role, Ecto.Enum, values: [:user, :assistant, :system, :tool]
          field :content, :string
          field :input_tokens, :integer
          field :output_tokens, :integer
          field :model_id, :string
          field :tool_call_id, :string

          belongs_to :chat, MyApp.LLM.Chat
          has_many :tool_calls, MyApp.LLM.ToolCall

          timestamps()
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      @doc """
      Converts this message to an ElixirLLM.Message struct.
      """
      def to_elixir_llm(msg) do
        ElixirLLM.Ecto.Message.do_to_elixir_llm(msg)
      end

      @doc """
      Returns total tokens (input + output) for this message.
      """
      def total_tokens(msg) do
        ElixirLLM.Ecto.Message.do_total_tokens(msg)
      end
    end
  end

  @doc false
  def do_to_elixir_llm(msg) do
    case msg.role do
      :user ->
        ElixirLLM.Message.user(msg.content)

      :assistant ->
        ElixirLLM.Message.assistant(msg.content, tool_calls: Map.get(msg, :tool_calls))

      :system ->
        ElixirLLM.Message.system(msg.content)

      :tool ->
        ElixirLLM.Message.tool_result(msg.tool_call_id, msg.content)
    end
  end

  @doc false
  def do_total_tokens(msg) do
    input = Map.get(msg, :input_tokens)
    output = Map.get(msg, :output_tokens)

    if is_integer(input) and is_integer(output) do
      input + output
    else
      nil
    end
  end
end
