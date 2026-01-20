defmodule ElixirLLM.Tool do
  @moduledoc """
  Behaviour and DSL for defining tools that can be called by LLMs.

  Tools allow AI models to execute code and interact with external systems.

  ## Module-based Tools (Recommended)

      defmodule MyApp.Tools.Weather do
        use ElixirLLM.Tool,
          name: "get_weather",
          description: "Gets current weather for a location"

        param :latitude, :string, required: true, description: "Latitude coordinate"
        param :longitude, :string, required: true, description: "Longitude coordinate"
        param :units, :string, required: false, description: "celsius or fahrenheit"

        @impl true
        def execute(%{latitude: lat, longitude: lon} = args) do
          units = Map.get(args, :units, "celsius")
          # Fetch weather data...
          {:ok, %{temperature: 22, conditions: "sunny", units: units}}
        end
      end

  ## Inline Tool Definition

  For simple cases, create tools inline:

      weather_tool = ElixirLLM.Tool.define(
        name: "get_weather",
        description: "Gets current weather",
        parameters: %{
          location: [type: :string, required: true]
        },
        execute: fn %{location: loc} ->
          {:ok, "Sunny, 22°C in \#{loc}"}
        end
      )
  """

  @type param_type :: :string | :integer | :number | :boolean | :array | :object

  @doc """
  Executes the tool with the given arguments.
  Arguments are passed as a map with atom keys.
  Return `{:ok, result}` or `{:error, reason}`.
  """
  @callback execute(args :: map()) :: {:ok, term()} | {:error, term()}

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour ElixirLLM.Tool

      Module.register_attribute(__MODULE__, :tool_params, accumulate: true)
      Module.put_attribute(__MODULE__, :tool_name, Keyword.get(opts, :name))
      Module.put_attribute(__MODULE__, :tool_description, Keyword.get(opts, :description))

      import ElixirLLM.Tool, only: [param: 2, param: 3]

      @before_compile ElixirLLM.Tool
    end
  end

  @doc """
  Defines a parameter for the tool.

  ## Options

    * `:required` - Whether the parameter is required (default: true)
    * `:description` - Description of the parameter
    * `:enum` - List of allowed values
    * `:default` - Default value

  ## Examples

      param :query, :string, required: true, description: "Search query"
      param :limit, :integer, required: false, default: 10
      param :format, :string, enum: ["json", "xml", "csv"]
  """
  defmacro param(name, type, opts \\ []) do
    quote do
      @tool_params {unquote(name), unquote(type), unquote(opts)}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    params = Module.get_attribute(env.module, :tool_params) |> Enum.reverse()
    name = Module.get_attribute(env.module, :tool_name)
    description = Module.get_attribute(env.module, :tool_description)

    param_map =
      for {param_name, type, opts} <- params, into: %{} do
        {param_name, Keyword.put(opts, :type, type)}
      end

    # Generate name from module if not provided
    generated_name =
      if name do
        name
      else
        env.module
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
      end

    quote do
      @doc "Returns the tool name."
      def name, do: unquote(generated_name)

      @doc "Returns the tool description."
      def description, do: unquote(description) || "No description provided"

      @doc "Returns the parameter schema."
      def parameters, do: unquote(Macro.escape(param_map))
    end
  end

  @doc """
  Creates an inline tool definition.

  ## Example

      tool = ElixirLLM.Tool.define(
        name: "calculator",
        description: "Performs basic math",
        parameters: %{
          expression: [type: :string, description: "Math expression", required: true]
        },
        execute: fn %{expression: expr} ->
          {:ok, 42}
        end
      )
  """
  @spec define(keyword()) :: map()
  def define(opts) do
    %{
      name: Keyword.fetch!(opts, :name),
      description: Keyword.fetch!(opts, :description),
      parameters: Keyword.get(opts, :parameters, %{}),
      execute: Keyword.fetch!(opts, :execute)
    }
  end

  @doc """
  Executes a tool (module or inline) with the given arguments.
  """
  @spec execute(module() | map(), map()) :: {:ok, term()} | {:error, term()}
  def execute(tool, args) when is_atom(tool) do
    normalized_args = normalize_args(args)
    tool.execute(normalized_args)
  end

  def execute(%{execute: execute_fn}, args) when is_function(execute_fn, 1) do
    normalized_args = normalize_args(args)
    execute_fn.(normalized_args)
  end

  @doc "Returns the tool name."
  @spec get_name(module() | map()) :: String.t()
  def get_name(tool) when is_atom(tool), do: tool.name()
  def get_name(%{name: name}), do: name

  @doc "Returns the tool description."
  @spec get_description(module() | map()) :: String.t()
  def get_description(tool) when is_atom(tool), do: tool.description()
  def get_description(%{description: desc}), do: desc

  @doc "Returns the tool parameters."
  @spec get_parameters(module() | map()) :: map()
  def get_parameters(tool) when is_atom(tool), do: tool.parameters()
  def get_parameters(%{parameters: params}), do: params

  defp normalize_args(args) when is_map(args) do
    Map.new(args, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      {key, value} -> {key, value}
    end)
  end
end
