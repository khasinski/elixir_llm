defmodule ElixirLLM.Providers.XAITest do
  use ExUnit.Case, async: true

  alias ElixirLLM.{Chunk, Response, ToolCall}
  alias ElixirLLM.Providers.XAI

  describe "parse_response/1" do
    test "parses a basic chat response" do
      body = %{
        "id" => "chatcmpl-123",
        "model" => "grok-2",
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "Hello! How can I help?"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 20,
          "total_tokens" => 30
        }
      }

      response = XAI.parse_response(body)

      assert %Response{} = response
      assert response.content == "Hello! How can I help?"
      assert response.model == "grok-2"
      assert response.input_tokens == 10
      assert response.output_tokens == 20
      assert response.total_tokens == 30
      assert response.finish_reason == :stop
    end

    test "parses response with tool calls" do
      body = %{
        "id" => "chatcmpl-123",
        "model" => "grok-2",
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => nil,
              "tool_calls" => [
                %{
                  "id" => "call_123",
                  "type" => "function",
                  "function" => %{
                    "name" => "get_weather",
                    "arguments" => "{\"city\": \"London\"}"
                  }
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ],
        "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 5}
      }

      response = XAI.parse_response(body)

      assert response.finish_reason == :tool_calls
      assert length(response.tool_calls) == 1
      [tool_call] = response.tool_calls
      assert %ToolCall{} = tool_call
      assert tool_call.id == "call_123"
      assert tool_call.name == "get_weather"
      assert tool_call.arguments == %{"city" => "London"}
    end
  end

  describe "parse_chunk/1" do
    test "parses content delta" do
      data = %{
        "choices" => [
          %{
            "delta" => %{"content" => "Hello"},
            "index" => 0
          }
        ]
      }

      chunk = XAI.parse_chunk(data)

      assert %Chunk{} = chunk
      assert chunk.content == "Hello"
    end

    test "parses finish reason" do
      data = %{
        "choices" => [
          %{
            "delta" => %{},
            "finish_reason" => "stop"
          }
        ]
      }

      chunk = XAI.parse_chunk(data)

      assert chunk.finish_reason == :stop
    end

    test "returns chunk with nil content for empty delta" do
      data = %{"choices" => [%{"delta" => %{}}]}

      chunk = XAI.parse_chunk(data)

      # Empty delta returns a Chunk struct with nil content
      assert %Chunk{} = chunk
      assert is_nil(chunk.content)
    end
  end

  describe "format_tools/1" do
    test "formats module-based tool" do
      defmodule TestTool do
        def name, do: "test_tool"
        def description, do: "A test tool"
        def parameters, do: %{input: [type: :string, description: "Input"]}
      end

      [formatted] = XAI.format_tools([TestTool])

      assert formatted.type == "function"
      assert formatted.function.name == "test_tool"
      assert formatted.function.description == "A test tool"
      # Parameters use atom keys
      assert formatted.function.parameters.type == "object"
      assert Map.has_key?(formatted.function.parameters.properties, :input)
    end

    test "formats inline tool map" do
      tool = %{
        name: "inline_tool",
        description: "An inline tool",
        parameters: %{query: [type: :string]}
      }

      [formatted] = XAI.format_tools([tool])

      assert formatted.function.name == "inline_tool"
      assert formatted.function.description == "An inline tool"
    end
  end
end
