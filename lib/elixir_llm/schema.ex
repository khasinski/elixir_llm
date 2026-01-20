defmodule ElixirLLM.Schema do
  @moduledoc """
  DSL for defining structured output schemas.

  Schemas ensure LLM responses conform to a specific structure, enabling
  type-safe parsing and validation.

  ## Example

      defmodule MyApp.Schemas.Person do
        use ElixirLLM.Schema

        field :name, :string, description: "Person's full name"
        field :age, :integer, description: "Age in years"
        field :email, :string, required: false

        embeds_one :address do
          field :street, :string
          field :city, :string
          field :country, :string
        end

        embeds_many :skills, of: :string
      end

      # Usage
      {:ok, %MyApp.Schemas.Person{} = person} =
        ElixirLLM.new()
        |> ElixirLLM.schema(MyApp.Schemas.Person)
        |> ElixirLLM.ask("Generate a software developer profile")

      person.name  # => "Alice Smith"
      person.age   # => 28
      person.address.city  # => "Berlin"

  ## Supported Types

    * `:string` - Text values
    * `:integer` - Whole numbers
    * `:number` - Decimal numbers (float)
    * `:boolean` - true/false
    * `:array` - Lists (use `of:` option for element type)
    * Embedded schemas via `embeds_one` and `embeds_many`
  """

  @type field_type :: :string | :integer | :number | :boolean | :array

  @doc false
  defmacro __using__(_opts) do
    quote do
      import ElixirLLM.Schema, only: [field: 2, field: 3, embeds_one: 2, embeds_many: 2]

      Module.register_attribute(__MODULE__, :schema_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :schema_embeds, accumulate: true)

      @before_compile ElixirLLM.Schema
    end
  end

  @doc """
  Defines a field in the schema.

  ## Options

    * `:description` - Description for the LLM
    * `:required` - Whether field is required (default: true)
    * `:enum` - List of allowed values
    * `:of` - Element type for arrays

  ## Examples

      field :name, :string, description: "Full name"
      field :age, :integer, required: true
      field :tags, :array, of: :string
      field :status, :string, enum: ["active", "inactive"]
  """
  defmacro field(name, type, opts \\ []) do
    quote do
      @schema_fields {unquote(name), unquote(type), unquote(opts)}
    end
  end

  @doc """
  Defines a nested embedded schema (one-to-one).

  ## Example

      embeds_one :address do
        field :street, :string
        field :city, :string
      end
  """
  defmacro embeds_one(name, do: block) do
    quote do
      # Create anonymous module for embedded schema
      embedded_module = Module.concat(__MODULE__, Macro.camelize(to_string(unquote(name))))

      defmodule embedded_module do
        use ElixirLLM.Schema
        unquote(block)
      end

      @schema_embeds {unquote(name), :one, embedded_module}
    end
  end

  @doc """
  Defines a nested embedded schema (one-to-many).

  ## Examples

      embeds_many :addresses do
        field :street, :string
        field :city, :string
      end

      # Or for simple arrays:
      embeds_many :tags, of: :string
  """
  defmacro embeds_many(name, opts_or_block)

  defmacro embeds_many(name, do: block) do
    quote do
      embedded_module = Module.concat(__MODULE__, Macro.camelize(to_string(unquote(name))))

      defmodule embedded_module do
        use ElixirLLM.Schema
        unquote(block)
      end

      @schema_embeds {unquote(name), :many, embedded_module}
    end
  end

  defmacro embeds_many(name, opts) when is_list(opts) do
    quote do
      @schema_fields {unquote(name), :array, unquote(opts)}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    fields = Module.get_attribute(env.module, :schema_fields) |> Enum.reverse()
    embeds = Module.get_attribute(env.module, :schema_embeds) |> Enum.reverse()

    # Generate struct keys
    struct_keys =
      Enum.map(fields, fn {name, _type, _opts} -> name end) ++
        Enum.map(embeds, fn {name, _cardinality, _mod} -> name end)

    # Generate JSON schema
    json_schema = generate_json_schema(fields, embeds)

    quote do
      defstruct unquote(struct_keys)

      @doc "Returns the JSON schema for this schema."
      def __json_schema__, do: unquote(Macro.escape(json_schema))

      @doc "Returns the field definitions."
      def __fields__, do: unquote(Macro.escape(fields))

      @doc "Returns the embed definitions."
      def __embeds__, do: unquote(Macro.escape(embeds))

      @doc "Parses a map into this schema struct."
      def parse(data) when is_map(data) do
        ElixirLLM.Schema.parse(__MODULE__, data)
      end
    end
  end

  defp generate_json_schema(fields, embeds) do
    properties =
      Enum.reduce(fields, %{}, fn {name, type, opts}, acc ->
        Map.put(acc, to_string(name), field_to_json_schema(type, opts))
      end)

    properties =
      Enum.reduce(embeds, properties, fn {name, cardinality, _mod}, acc ->
        # We'll resolve the embedded schema at runtime
        schema =
          case cardinality do
            :one -> %{type: "object", properties: %{}}
            :many -> %{type: "array", items: %{type: "object"}}
          end

        Map.put(acc, to_string(name), schema)
      end)

    required =
      fields
      |> Enum.filter(fn {_name, _type, opts} -> Keyword.get(opts, :required, true) end)
      |> Enum.map(fn {name, _type, _opts} -> to_string(name) end)

    required =
      required ++
        (embeds
         |> Enum.map(fn {name, _cardinality, _mod} -> to_string(name) end))

    %{
      type: "object",
      properties: properties,
      required: required
    }
  end

  defp field_to_json_schema(type, opts) do
    base =
      case type do
        :string -> %{type: "string"}
        :integer -> %{type: "integer"}
        :number -> %{type: "number"}
        :boolean -> %{type: "boolean"}
        :array -> %{type: "array", items: items_schema(opts)}
      end

    base
    |> maybe_add_description(opts)
    |> maybe_add_enum(opts)
  end

  defp items_schema(opts) do
    case Keyword.get(opts, :of, :string) do
      :string -> %{type: "string"}
      :integer -> %{type: "integer"}
      :number -> %{type: "number"}
      :boolean -> %{type: "boolean"}
      _ -> %{type: "string"}
    end
  end

  defp maybe_add_description(schema, opts) do
    case Keyword.get(opts, :description) do
      nil -> schema
      desc -> Map.put(schema, :description, desc)
    end
  end

  defp maybe_add_enum(schema, opts) do
    case Keyword.get(opts, :enum) do
      nil -> schema
      values -> Map.put(schema, :enum, values)
    end
  end

  @doc """
  Parses data into a schema struct.
  """
  @spec parse(module(), map()) :: struct()
  def parse(schema_module, data) when is_map(data) do
    fields = schema_module.__fields__()
    embeds = schema_module.__embeds__()

    parsed =
      Enum.reduce(fields, %{}, fn {name, type, _opts}, acc ->
        key = to_string(name)
        value = Map.get(data, key) || Map.get(data, name)
        Map.put(acc, name, cast_value(value, type))
      end)

    parsed =
      Enum.reduce(embeds, parsed, fn {name, cardinality, embed_mod}, acc ->
        key = to_string(name)
        value = Map.get(data, key) || Map.get(data, name)

        casted =
          case {cardinality, value} do
            {_, nil} -> nil
            {:one, map} -> parse(embed_mod, map)
            {:many, list} when is_list(list) -> Enum.map(list, &parse(embed_mod, &1))
            _ -> nil
          end

        Map.put(acc, name, casted)
      end)

    struct(schema_module, parsed)
  end

  defp cast_value(nil, _type), do: nil
  defp cast_value(value, :string) when is_binary(value), do: value
  defp cast_value(value, :string), do: to_string(value)
  defp cast_value(value, :integer) when is_integer(value), do: value
  defp cast_value(value, :integer) when is_binary(value), do: String.to_integer(value)
  defp cast_value(value, :number) when is_number(value), do: value
  defp cast_value(value, :number) when is_binary(value), do: String.to_float(value)
  defp cast_value(value, :boolean) when is_boolean(value), do: value
  defp cast_value("true", :boolean), do: true
  defp cast_value("false", :boolean), do: false
  defp cast_value(value, :array) when is_list(value), do: value
  defp cast_value(value, _type), do: value

  @doc """
  Returns the JSON schema for a schema module.
  """
  @spec json_schema(module()) :: map()
  def json_schema(schema_module) do
    base_schema = schema_module.__json_schema__()
    embeds = schema_module.__embeds__()

    # Resolve embedded schemas
    properties =
      Enum.reduce(embeds, base_schema.properties, fn {name, cardinality, embed_mod}, acc ->
        embed_schema = json_schema(embed_mod)

        resolved =
          case cardinality do
            :one -> embed_schema
            :many -> %{type: "array", items: embed_schema}
          end

        Map.put(acc, to_string(name), resolved)
      end)

    %{base_schema | properties: properties}
  end
end
