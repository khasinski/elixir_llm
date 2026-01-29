defmodule ElixirLLM.Providers.BedrockTest do
  use ExUnit.Case, async: true

  alias ElixirLLM.{Chunk, Response, ToolCall}
  alias ElixirLLM.Providers.Bedrock

  describe "parse_response/2" do
    test "parses a basic Converse API response" do
      body = %{
        "output" => %{
          "message" => %{
            "role" => "assistant",
            "content" => [%{"text" => "Hello from Bedrock!"}]
          }
        },
        "stopReason" => "end_turn",
        "usage" => %{
          "inputTokens" => 10,
          "outputTokens" => 20
        }
      }

      response = Bedrock.parse_response(body, "bedrock/claude-sonnet-4")

      assert %Response{} = response
      assert response.content == "Hello from Bedrock!"
      assert response.model == "bedrock/claude-sonnet-4"
      assert response.input_tokens == 10
      assert response.output_tokens == 20
      assert response.finish_reason == :stop
    end

    test "parses response with tool use" do
      body = %{
        "output" => %{
          "message" => %{
            "role" => "assistant",
            "content" => [
              %{
                "toolUse" => %{
                  "toolUseId" => "tool_123",
                  "name" => "get_weather",
                  "input" => %{"city" => "London"}
                }
              }
            ]
          }
        },
        "stopReason" => "tool_use",
        "usage" => %{}
      }

      response = Bedrock.parse_response(body, "bedrock/claude-sonnet-4")

      assert response.finish_reason == :tool_calls
      assert length(response.tool_calls) == 1
      [tool_call] = response.tool_calls
      assert %ToolCall{} = tool_call
      assert tool_call.id == "tool_123"
      assert tool_call.name == "get_weather"
      assert tool_call.arguments == %{"city" => "London"}
    end

    test "parses response with mixed content and tool use" do
      body = %{
        "output" => %{
          "message" => %{
            "role" => "assistant",
            "content" => [
              %{"text" => "Let me check that for you."},
              %{
                "toolUse" => %{
                  "toolUseId" => "tool_456",
                  "name" => "search",
                  "input" => %{"query" => "test"}
                }
              }
            ]
          }
        },
        "stopReason" => "tool_use",
        "usage" => %{}
      }

      response = Bedrock.parse_response(body, "bedrock/claude-3-haiku")

      assert response.content == "Let me check that for you."
      assert length(response.tool_calls) == 1
    end

    test "handles empty content" do
      body = %{
        "output" => %{
          "message" => %{
            "role" => "assistant",
            "content" => []
          }
        },
        "stopReason" => "end_turn",
        "usage" => %{}
      }

      response = Bedrock.parse_response(body, "model")

      assert is_nil(response.content)
    end
  end

  describe "parse_chunk/1" do
    test "parses content block delta" do
      data = %{
        "contentBlockDelta" => %{
          "delta" => %{"text" => "Hello"}
        }
      }

      chunk = Bedrock.parse_chunk(data)

      assert %Chunk{} = chunk
      assert chunk.content == "Hello"
    end

    test "parses message stop with reason" do
      data = %{
        "messageStop" => %{
          "stopReason" => "end_turn"
        }
      }

      chunk = Bedrock.parse_chunk(data)

      assert chunk.finish_reason == :stop
    end

    test "parses metadata with usage" do
      data = %{
        "metadata" => %{
          "usage" => %{
            "inputTokens" => 100,
            "outputTokens" => 200
          }
        }
      }

      chunk = Bedrock.parse_chunk(data)

      assert chunk.input_tokens == 100
      assert chunk.output_tokens == 200
    end

    test "returns nil for message start" do
      data = %{
        "messageStart" => %{"role" => "assistant"}
      }

      chunk = Bedrock.parse_chunk(data)

      assert is_nil(chunk)
    end
  end

  describe "format_tools/1" do
    test "formats tools for Bedrock Converse API" do
      tool = %{
        name: "calculator",
        description: "Performs calculations",
        parameters: %{expression: [type: :string, description: "Math expression"]}
      }

      result = Bedrock.format_tools([tool])

      assert is_list(result)
      assert length(result) == 1
      [tool_spec] = result
      assert tool_spec.toolSpec.name == "calculator"
      assert tool_spec.toolSpec.description == "Performs calculations"
      assert tool_spec.toolSpec.inputSchema.json
    end
  end
end
