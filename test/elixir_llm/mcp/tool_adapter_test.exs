defmodule ElixirLLM.MCP.ToolAdapterTest do
  use ExUnit.Case, async: true

  alias ElixirLLM.MCP.ToolAdapter

  describe "convert_schema/1" do
    test "converts nil to empty map" do
      assert ToolAdapter.convert_schema(nil) == %{}
    end

    test "converts empty properties" do
      schema = %{"type" => "object", "properties" => %{}}
      assert ToolAdapter.convert_schema(schema) == %{}
    end

    test "converts simple string property" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "The name"}
        }
      }

      result = ToolAdapter.convert_schema(schema)

      assert result[:name][:type] == :string
      assert result[:name][:description] == "The name"
    end

    test "converts multiple properties with different types" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "count" => %{"type" => "integer"},
          "enabled" => %{"type" => "boolean"},
          "score" => %{"type" => "number"}
        }
      }

      result = ToolAdapter.convert_schema(schema)

      assert result[:name][:type] == :string
      assert result[:count][:type] == :integer
      assert result[:enabled][:type] == :boolean
      assert result[:score][:type] == :number
    end

    test "marks required properties" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "required_field" => %{"type" => "string"},
          "optional_field" => %{"type" => "string"}
        },
        "required" => ["required_field"]
      }

      result = ToolAdapter.convert_schema(schema)

      assert result[:required_field][:required] == true
      refute result[:optional_field][:required]
    end

    test "includes enum values" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "status" => %{
            "type" => "string",
            "enum" => ["pending", "active", "done"]
          }
        }
      }

      result = ToolAdapter.convert_schema(schema)

      assert result[:status][:enum] == ["pending", "active", "done"]
    end

    test "sanitizes property names with special characters" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "my-property" => %{"type" => "string"},
          "another.property" => %{"type" => "string"},
          "spaced property" => %{"type" => "string"}
        }
      }

      result = ToolAdapter.convert_schema(schema)

      # Properties should be converted to valid atom names
      assert Map.has_key?(result, :my_property)
      assert Map.has_key?(result, :another_property)
      assert Map.has_key?(result, :spaced_property)
    end

    test "handles property names starting with numbers" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "123field" => %{"type" => "string"}
        }
      }

      result = ToolAdapter.convert_schema(schema)

      # Should prefix with underscore
      assert Map.has_key?(result, :_123field)
    end

    test "returns empty map for non-object schemas" do
      assert ToolAdapter.convert_schema(%{"type" => "string"}) == %{}
      assert ToolAdapter.convert_schema(%{"type" => "array"}) == %{}
    end
  end

  describe "convert_tool/2" do
    test "converts MCP tool to ElixirLLM format" do
      mcp_tool = %{
        "name" => "read_file",
        "description" => "Read file contents",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "path" => %{"type" => "string", "description" => "File path"}
          },
          "required" => ["path"]
        }
      }

      # Create a mock MCP connection
      mock_conn = %ElixirLLM.MCP{pid: self(), name: "test", tools: [], resources: [], prompts: []}

      result = ToolAdapter.convert_tool(mcp_tool, mock_conn)

      assert result.name == "read_file"
      assert result.description == "Read file contents"
      assert result.parameters[:path][:type] == :string
      assert result.parameters[:path][:required] == true
      assert is_function(result.execute, 1)
    end

    test "provides default description when missing" do
      mcp_tool = %{
        "name" => "some_tool",
        "inputSchema" => nil
      }

      mock_conn = %ElixirLLM.MCP{pid: self(), name: "test", tools: [], resources: [], prompts: []}

      result = ToolAdapter.convert_tool(mcp_tool, mock_conn)

      assert result.description == "MCP tool: some_tool"
    end
  end
end
