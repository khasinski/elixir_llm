defmodule ElixirLLM.Providers.DeepSeekTest do
  use ExUnit.Case, async: true

  alias ElixirLLM.{Chunk, Response}
  alias ElixirLLM.Providers.DeepSeek

  describe "parse_response/1" do
    test "parses a basic chat response" do
      body = %{
        "id" => "chatcmpl-123",
        "model" => "deepseek-chat",
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "Hello from DeepSeek!"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 15,
          "completion_tokens" => 25,
          "total_tokens" => 40
        }
      }

      response = DeepSeek.parse_response(body)

      assert %Response{} = response
      assert response.content == "Hello from DeepSeek!"
      assert response.model == "deepseek-chat"
      assert response.input_tokens == 15
      assert response.output_tokens == 25
      assert response.finish_reason == :stop
    end

    test "parses response with reasoning content (DeepSeek Reasoner)" do
      body = %{
        "id" => "chatcmpl-123",
        "model" => "deepseek-reasoner",
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "The answer is 42.",
              "reasoning_content" => "Let me think step by step...\n1. First consideration...\n2. Second consideration..."
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 50,
          "total_tokens" => 60
        }
      }

      response = DeepSeek.parse_response(body)

      assert response.content == "The answer is 42."
      assert response.thinking == "Let me think step by step...\n1. First consideration...\n2. Second consideration..."
    end

    test "handles missing reasoning content" do
      body = %{
        "model" => "deepseek-chat",
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "No reasoning here"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{}
      }

      response = DeepSeek.parse_response(body)

      assert response.content == "No reasoning here"
      assert is_nil(response.thinking)
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

      chunk = DeepSeek.parse_chunk(data)

      assert %Chunk{} = chunk
      assert chunk.content == "Hello"
    end

    test "parses chunk with empty delta" do
      # DeepSeek uses standard OpenAI streaming format
      # reasoning_content is only in the full response, not in streaming chunks
      data = %{
        "choices" => [
          %{
            "delta" => %{},
            "index" => 0
          }
        ]
      }

      chunk = DeepSeek.parse_chunk(data)

      assert %Chunk{} = chunk
      assert is_nil(chunk.content)
    end

    test "parses usage in chunk" do
      data = %{
        "choices" => [%{"delta" => %{}}],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 20
        }
      }

      chunk = DeepSeek.parse_chunk(data)

      assert chunk.input_tokens == 10
      assert chunk.output_tokens == 20
    end
  end

  describe "format_tools/1" do
    test "formats tools in OpenAI-compatible format" do
      tool = %{
        name: "search",
        description: "Search the web",
        parameters: %{query: [type: :string, required: true]}
      }

      [formatted] = DeepSeek.format_tools([tool])

      assert formatted.type == "function"
      assert formatted.function.name == "search"
    end
  end
end
