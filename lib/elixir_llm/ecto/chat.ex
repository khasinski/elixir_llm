defmodule ElixirLLM.Ecto.Chat do
  @moduledoc """
  Ecto integration for persisted chats.

  Add this to your Ecto schema to enable LLM chat persistence:

      defmodule MyApp.LLM.Chat do
        use Ecto.Schema
        use ElixirLLM.Ecto.Chat, message_schema: MyApp.LLM.Message

        schema "llm_chats" do
          field :model_id, :string
          field :instructions, :string
          has_many :messages, MyApp.LLM.Message
          timestamps()
        end
      end

  This adds the following functions to your schema:

    * `ask/3` - Send a message and persist the response
    * `to_elixir_llm/1` - Convert to an ElixirLLM.Chat struct
  """

  defmacro __using__(opts) do
    message_schema = Keyword.get(opts, :message_schema)

    quote do
      @elixir_llm_message_schema unquote(message_schema)

      @doc """
      Sends a message to the LLM and persists the response.

      ## Options

        * `:repo` - The Ecto repo to use
        * `:stream` - Callback function for streaming responses
        * `:tools` - List of tools to make available

      ## Example

          {:ok, response, chat} = MyApp.LLM.Chat.ask(chat, "Hello!", repo: MyApp.Repo)
      """
      def ask(chat, message, opts \\ []) do
        ElixirLLM.Ecto.Chat.do_ask(__MODULE__, @elixir_llm_message_schema, chat, message, opts)
      end

      @doc """
      Converts this Ecto schema to an ElixirLLM.Chat struct.
      """
      def to_elixir_llm(chat, opts \\ []) do
        ElixirLLM.Ecto.Chat.do_to_elixir_llm(chat, opts)
      end
    end
  end

  @doc false
  def do_ask(_chat_module, message_schema, chat, message, opts) do
    repo = Keyword.get(opts, :repo) || get_repo()
    tools = Keyword.get(opts, :tools, [])
    stream_callback = Keyword.get(opts, :stream)

    # Ensure messages are preloaded
    chat = repo.preload(chat, :messages)

    # Convert to ElixirLLM.Chat
    llm_chat = do_to_elixir_llm(chat, tools: tools)

    # Persist user message
    {:ok, _user_msg} =
      repo.insert(
        struct(message_schema, %{
          chat_id: chat.id,
          role: :user,
          content: message
        })
      )

    # Build ask options
    ask_opts =
      if stream_callback do
        [stream: stream_callback]
      else
        []
      end

    # Make the API call
    case ElixirLLM.ask(llm_chat, message, ask_opts) do
      {:ok, response, _updated_llm_chat} ->
        # Persist assistant message
        {:ok, _assistant_msg} =
          repo.insert(
            struct(message_schema, %{
              chat_id: chat.id,
              role: :assistant,
              content: response.content,
              input_tokens: response.input_tokens,
              output_tokens: response.output_tokens,
              model_id: response.model
            })
          )

        # Reload chat with messages
        updated_chat = repo.preload(chat, :messages, force: true)
        {:ok, response, updated_chat}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  def do_to_elixir_llm(chat, opts \\ []) do
    tools = Keyword.get(opts, :tools, [])

    # Handle Ecto.Association.NotLoaded - check if it's a list (loaded) or not
    raw_messages =
      if is_list(chat.messages) do
        chat.messages
      else
        []
      end

    messages =
      raw_messages
      |> Enum.sort_by(& &1.inserted_at)
      |> Enum.map(&message_to_elixir_llm/1)

    llm_chat = ElixirLLM.new()

    llm_chat =
      if chat.model_id do
        ElixirLLM.model(llm_chat, chat.model_id)
      else
        llm_chat
      end

    llm_chat =
      if Map.get(chat, :instructions) do
        ElixirLLM.instructions(llm_chat, chat.instructions)
      else
        llm_chat
      end

    llm_chat = ElixirLLM.Chat.add_messages(llm_chat, messages)
    llm_chat = ElixirLLM.tools(llm_chat, tools)

    llm_chat
  end

  defp message_to_elixir_llm(msg) do
    case msg.role do
      :user -> ElixirLLM.Message.user(msg.content)
      :assistant -> ElixirLLM.Message.assistant(msg.content)
      :system -> ElixirLLM.Message.system(msg.content)
      :tool -> ElixirLLM.Message.tool_result(msg.tool_call_id, msg.content)
    end
  end

  defp get_repo do
    Application.get_env(:elixir_llm, :ecto, [])[:repo] ||
      raise "No repo configured. Pass :repo option or configure in application config."
  end
end
