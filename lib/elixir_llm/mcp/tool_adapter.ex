defmodule ElixirLLM.MCP.ToolAdapter do
  @moduledoc """
  Adapts MCP tools to ElixirLLM Tool format.

  This module converts MCP tool definitions to the format expected by ElixirLLM,
  allowing MCP tools to be used seamlessly with any LLM provider.

  ## Examples

      # Get tools from MCP connection
      {:ok, conn} = ElixirLLM.MCP.connect("npx", ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"])

      # Convert to ElixirLLM tools
      tools = ElixirLLM.MCP.ToolAdapter.to_elixir_llm_tools(conn)

      # Use with chat
      {:ok, response, _} =
        ElixirLLM.new()
        |> ElixirLLM.model("gpt-4o")
        |> ElixirLLM.tools(tools)
        |> ElixirLLM.ask("List files in /tmp")
  """

  alias ElixirLLM.MCP

  @doc """
  Converts MCP tools to ElixirLLM tool format.

  Returns a list of inline tool maps that can be passed to `ElixirLLM.tool/2`
  or `ElixirLLM.tools/2`.

  ## Example

      tools = ElixirLLM.MCP.ToolAdapter.to_elixir_llm_tools(conn)
      chat |> ElixirLLM.tools(tools)
  """
  @spec to_elixir_llm_tools(MCP.t()) :: [map()]
  def to_elixir_llm_tools(%MCP{} = conn) do
    {:ok, mcp_tools} = MCP.list_tools(conn)

    Enum.map(mcp_tools, fn tool ->
      %{
        name: tool["name"],
        description: tool["description"] || "MCP tool: #{tool["name"]}",
        parameters: convert_schema(tool["inputSchema"]),
        execute: fn args ->
          MCP.call_tool(conn, tool["name"], args)
        end
      }
    end)
  end

  @doc """
  Converts a single MCP tool definition to ElixirLLM format.
  """
  @spec convert_tool(map(), MCP.t()) :: map()
  def convert_tool(tool, conn) do
    %{
      name: tool["name"],
      description: tool["description"] || "MCP tool: #{tool["name"]}",
      parameters: convert_schema(tool["inputSchema"]),
      execute: fn args ->
        MCP.call_tool(conn, tool["name"], args)
      end
    }
  end

  @doc """
  Converts MCP JSON Schema to ElixirLLM parameter format.

  Parameter names are sanitized to valid Elixir atoms (alphanumeric and underscores).
  """
  @spec convert_schema(map() | nil) :: map()
  def convert_schema(nil), do: %{}

  def convert_schema(%{"type" => "object", "properties" => properties} = schema) do
    required = schema["required"] || []

    properties
    |> Enum.map(fn {name, prop} ->
      {safe_to_atom(name), convert_property(prop, name in required)}
    end)
    |> Map.new()
  end

  def convert_schema(_), do: %{}

  # Safely convert a string to an atom, sanitizing invalid characters
  defp safe_to_atom(name) when is_binary(name) do
    name
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
    |> String.replace(~r/^(\d)/, "_\\1")
    |> String.to_atom()
  end

  defp convert_property(prop, required) do
    base = [
      type: convert_type(prop["type"]),
      description: prop["description"]
    ]

    base =
      if required do
        Keyword.put(base, :required, true)
      else
        base
      end

    # Add enum if present
    base =
      if prop["enum"] do
        Keyword.put(base, :enum, prop["enum"])
      else
        base
      end

    base
  end

  defp convert_type("string"), do: :string
  defp convert_type("number"), do: :number
  defp convert_type("integer"), do: :integer
  defp convert_type("boolean"), do: :boolean
  defp convert_type("array"), do: :array
  defp convert_type("object"), do: :object
  defp convert_type(_), do: :string
end
