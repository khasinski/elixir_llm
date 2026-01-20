defmodule Mix.Tasks.ElixirLlm.Gen.Ecto do
  @shortdoc "Generates Ecto schemas and migrations for ElixirLLM"

  @moduledoc """
  Generates Ecto schemas and migrations for ElixirLLM chat persistence.

      $ mix elixir_llm.gen.ecto

  This will generate:

    * `lib/my_app/llm/chat.ex` - Chat schema
    * `lib/my_app/llm/message.ex` - Message schema
    * `lib/my_app/llm/tool_call.ex` - ToolCall schema
    * `priv/repo/migrations/*_create_llm_tables.exs` - Migration

  ## Options

    * `--context` - The context module name (default: LLM)
    * `--no-migration` - Skip migration generation
  """

  use Mix.Task

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [context: :string, migration: :boolean])

    context = opts[:context] || "LLM"
    generate_migration = Keyword.get(opts, :migration, true)

    app_module = get_app_module()
    context_module = "#{app_module}.#{context}"

    # Generate schemas
    generate_chat_schema(app_module, context_module)
    generate_message_schema(app_module, context_module)
    generate_tool_call_schema(app_module, context_module)

    # Generate migration
    if generate_migration do
      generate_migration(app_module)
    end

    Mix.shell().info("""

    ElixirLLM Ecto schemas generated!

    Add to your config/config.exs:

        config :elixir_llm, :ecto,
          repo: #{app_module}.Repo,
          chat_schema: #{context_module}.Chat,
          message_schema: #{context_module}.Message,
          tool_call_schema: #{context_module}.ToolCall

    Then run migrations:

        $ mix ecto.migrate
    """)
  end

  defp get_app_module do
    Mix.Project.config()[:app]
    |> to_string()
    |> Macro.camelize()
  end

  defp generate_chat_schema(app_module, context_module) do
    content = """
    defmodule #{context_module}.Chat do
      use Ecto.Schema
      use ElixirLLM.Ecto.Chat, message_schema: #{context_module}.Message

      import Ecto.Changeset

      schema "llm_chats" do
        field :model_id, :string
        field :instructions, :string
        field :metadata, :map, default: %{}

        has_many :messages, #{context_module}.Message

        timestamps()
      end

      @doc false
      def changeset(chat, attrs) do
        chat
        |> cast(attrs, [:model_id, :instructions, :metadata])
      end

      @doc "Creates a new chat."
      def create(attrs \\\\ %{}) do
        %__MODULE__{}
        |> changeset(attrs)
        |> #{app_module}.Repo.insert()
      end
    end
    """

    path = Path.join(["lib", Macro.underscore(to_string(app_module)), "llm", "chat.ex"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    Mix.shell().info("Generated #{path}")
  end

  defp generate_message_schema(app_module, context_module) do
    content = """
    defmodule #{context_module}.Message do
      use Ecto.Schema
      use ElixirLLM.Ecto.Message

      import Ecto.Changeset

      schema "llm_messages" do
        field :role, Ecto.Enum, values: [:user, :assistant, :system, :tool]
        field :content, :string
        field :input_tokens, :integer
        field :output_tokens, :integer
        field :model_id, :string
        field :tool_call_id, :string

        belongs_to :chat, #{context_module}.Chat
        has_many :tool_calls, #{context_module}.ToolCall

        timestamps()
      end

      @doc false
      def changeset(message, attrs) do
        message
        |> cast(attrs, [:role, :content, :input_tokens, :output_tokens, :model_id, :tool_call_id, :chat_id])
        |> validate_required([:role, :chat_id])
      end
    end
    """

    path = Path.join(["lib", Macro.underscore(to_string(app_module)), "llm", "message.ex"])
    File.write!(path, content)
    Mix.shell().info("Generated #{path}")
  end

  defp generate_tool_call_schema(app_module, context_module) do
    content = """
    defmodule #{context_module}.ToolCall do
      use Ecto.Schema
      use ElixirLLM.Ecto.ToolCall

      import Ecto.Changeset

      schema "llm_tool_calls" do
        field :call_id, :string
        field :tool_name, :string
        field :arguments, :map, default: %{}
        field :result, :string

        belongs_to :message, #{context_module}.Message

        timestamps()
      end

      @doc false
      def changeset(tool_call, attrs) do
        tool_call
        |> cast(attrs, [:call_id, :tool_name, :arguments, :result, :message_id])
        |> validate_required([:call_id, :tool_name, :message_id])
      end
    end
    """

    path = Path.join(["lib", Macro.underscore(to_string(app_module)), "llm", "tool_call.ex"])
    File.write!(path, content)
    Mix.shell().info("Generated #{path}")
  end

  defp generate_migration(app_module) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")

    content = """
    defmodule #{app_module}.Repo.Migrations.CreateLlmTables do
      use Ecto.Migration

      def change do
        create table(:llm_chats) do
          add :model_id, :string
          add :instructions, :text
          add :metadata, :map, default: %{}

          timestamps()
        end

        create table(:llm_messages) do
          add :role, :string, null: false
          add :content, :text
          add :input_tokens, :integer
          add :output_tokens, :integer
          add :model_id, :string
          add :tool_call_id, :string

          add :chat_id, references(:llm_chats, on_delete: :delete_all), null: false

          timestamps()
        end

        create index(:llm_messages, [:chat_id])

        create table(:llm_tool_calls) do
          add :call_id, :string, null: false
          add :tool_name, :string, null: false
          add :arguments, :map, default: %{}
          add :result, :text

          add :message_id, references(:llm_messages, on_delete: :delete_all), null: false

          timestamps()
        end

        create index(:llm_tool_calls, [:message_id])
      end
    end
    """

    path = Path.join(["priv", "repo", "migrations", "#{timestamp}_create_llm_tables.exs"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    Mix.shell().info("Generated #{path}")
  end
end
