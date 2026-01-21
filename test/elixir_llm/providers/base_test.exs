defmodule ElixirLLM.Providers.BaseTest do
  use ExUnit.Case

  alias ElixirLLM.{Chunk, Response, ToolCall}
  alias ElixirLLM.Providers.Base

  describe "parse_sse_data/1" do
    test "parses single SSE event" do
      data = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n"
      result = Base.parse_sse_data(data)

      assert [%{"choices" => [%{"delta" => %{"content" => "Hello"}}]}] = result
    end

    test "parses multiple SSE events" do
      data = """
      data: {"choices":[{"delta":{"content":"Hello"}}]}

      data: {"choices":[{"delta":{"content":" World"}}]}

      """

      result = Base.parse_sse_data(data)
      assert length(result) == 2
    end

    test "filters out [DONE] marker" do
      data = """
      data: {"choices":[{"delta":{"content":"Hi"}}]}

      data: [DONE]

      """

      result = Base.parse_sse_data(data)
      assert length(result) == 1
    end

    test "handles invalid JSON gracefully" do
      data = "data: not valid json\n\n"
      result = Base.parse_sse_data(data)
      assert result == []
    end
  end

  describe "parse_ndjson_data/1" do
    test "parses NDJSON lines" do
      data = """
      {"message":{"content":"Hello"}}
      {"message":{"content":" World"}}
      """

      result = Base.parse_ndjson_data(data)
      assert length(result) == 2
    end

    test "handles SSE-wrapped NDJSON" do
      data = "data: {\"message\":{\"content\":\"Hello\"}}\n"
      result = Base.parse_ndjson_data(data)
      assert [%{"message" => %{"content" => "Hello"}}] = result
    end

    test "filters empty lines" do
      data = "\n{\"key\":\"value\"}\n\n"
      result = Base.parse_ndjson_data(data)
      assert length(result) == 1
    end
  end

  describe "parse_chat_response/1" do
    test "parses OpenAI-style response" do
      body = %{
        "choices" => [
          %{
            "message" => %{
              "content" => "Hello!",
              "tool_calls" => nil
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 5,
          "total_tokens" => 15
        },
        "model" => "gpt-4o"
      }

      response = Base.parse_chat_response(body)

      assert %Response{} = response
      assert response.content == "Hello!"
      assert response.model == "gpt-4o"
      assert response.input_tokens == 10
      assert response.output_tokens == 5
      assert response.total_tokens == 15
      assert response.finish_reason == :stop
    end

    test "parses response with tool calls" do
      body = %{
        "choices" => [
          %{
            "message" => %{
              "content" => nil,
              "tool_calls" => [
                %{
                  "id" => "call_123",
                  "function" => %{
                    "name" => "get_weather",
                    "arguments" => "{\"location\":\"NYC\"}"
                  }
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ],
        "usage" => %{},
        "model" => "gpt-4o"
      }

      response = Base.parse_chat_response(body)

      assert [%ToolCall{} = tc] = response.tool_calls
      assert tc.id == "call_123"
      assert tc.name == "get_weather"
      assert tc.arguments == %{"location" => "NYC"}
      assert response.finish_reason == :tool_calls
    end
  end

  describe "parse_stream_chunk/1" do
    test "parses content delta" do
      data = %{
        "choices" => [
          %{
            "delta" => %{
              "content" => "Hello"
            },
            "finish_reason" => nil
          }
        ],
        "model" => "gpt-4o"
      }

      chunk = Base.parse_stream_chunk(data)

      assert %Chunk{} = chunk
      assert chunk.content == "Hello"
      assert chunk.model == "gpt-4o"
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

      chunk = Base.parse_stream_chunk(data)
      assert chunk.finish_reason == :stop
    end

    test "returns nil for empty choices" do
      data = %{"choices" => []}
      assert Base.parse_stream_chunk(data) == nil
    end
  end

  describe "parse_tool_calls/1" do
    test "returns nil for nil input" do
      assert Base.parse_tool_calls(nil) == nil
    end

    test "returns nil for empty list" do
      assert Base.parse_tool_calls([]) == nil
    end

    test "parses tool calls with JSON string arguments" do
      tool_calls = [
        %{
          "id" => "call_abc",
          "function" => %{
            "name" => "calculator",
            "arguments" => "{\"expr\":\"2+2\"}"
          }
        }
      ]

      result = Base.parse_tool_calls(tool_calls)

      assert [%ToolCall{} = tc] = result
      assert tc.id == "call_abc"
      assert tc.name == "calculator"
      assert tc.arguments == %{"expr" => "2+2"}
    end

    test "handles pre-decoded map arguments" do
      tool_calls = [
        %{
          "id" => "call_abc",
          "function" => %{
            "name" => "calc",
            "arguments" => %{"a" => 1}
          }
        }
      ]

      result = Base.parse_tool_calls(tool_calls)
      assert [%ToolCall{arguments: %{"a" => 1}}] = result
    end
  end

  describe "format_tools_openai/1" do
    test "formats tool module" do
      defmodule TestTool do
        def name, do: "test_tool"
        def description, do: "A test tool"
        def parameters, do: %{input: [type: :string, description: "Input text"]}
      end

      [formatted] = Base.format_tools_openai([TestTool])

      assert formatted.type == "function"
      assert formatted.function.name == "test_tool"
      assert formatted.function.description == "A test tool"
      assert formatted.function.parameters.type == "object"
      assert formatted.function.parameters.properties.input.type == "string"
    end

    test "formats tool map" do
      tool = %{
        name: "my_tool",
        description: "Does stuff",
        parameters: %{x: [type: :integer, required: true]}
      }

      [formatted] = Base.format_tools_openai([tool])

      assert formatted.function.name == "my_tool"
      assert formatted.function.parameters.required == ["x"]
    end
  end

  describe "format_messages_openai/1" do
    test "formats user message" do
      messages = [%{role: :user, content: "Hello"}]
      result = Base.format_messages_openai(messages)

      assert [%{role: "user", content: "Hello"}] = result
    end

    test "formats assistant message" do
      messages = [%{role: :assistant, content: "Hi there", tool_calls: nil}]
      result = Base.format_messages_openai(messages)

      assert [%{role: "assistant", content: "Hi there"}] = result
    end

    test "formats system message" do
      messages = [%{role: :system, content: "You are helpful"}]
      result = Base.format_messages_openai(messages)

      assert [%{role: "system", content: "You are helpful"}] = result
    end

    test "formats tool result message" do
      messages = [%{role: :tool, content: "42", tool_call_id: "call_123"}]
      result = Base.format_messages_openai(messages)

      assert [%{role: "tool", content: "42", tool_call_id: "call_123"}] = result
    end

    test "formats assistant message with tool calls" do
      tc = ToolCall.new("call_1", "calculator", %{"expr" => "2+2"})
      messages = [%{role: :assistant, content: nil, tool_calls: [tc]}]

      result = Base.format_messages_openai(messages)

      assert [msg] = result
      assert msg.role == "assistant"
      assert [formatted_tc] = msg.tool_calls
      assert formatted_tc.id == "call_1"
      assert formatted_tc.function.name == "calculator"
    end
  end

  describe "accumulate_chunk/2" do
    test "accumulates content" do
      acc = Base.initial_accumulator()
      chunk1 = %Chunk{content: "Hello"}
      chunk2 = %Chunk{content: " World"}

      acc = Base.accumulate_chunk(acc, chunk1)
      acc = Base.accumulate_chunk(acc, chunk2)

      assert acc.content == "Hello World"
    end

    test "preserves first non-nil values" do
      acc = Base.initial_accumulator()
      chunk1 = %Chunk{model: "gpt-4o", input_tokens: 10}
      chunk2 = %Chunk{model: nil, output_tokens: 5, finish_reason: :stop}

      acc = Base.accumulate_chunk(acc, chunk1)
      acc = Base.accumulate_chunk(acc, chunk2)

      assert acc.model == "gpt-4o"
      assert acc.input_tokens == 10
      assert acc.output_tokens == 5
      assert acc.finish_reason == :stop
    end

    test "merges tool calls" do
      acc = Base.initial_accumulator()
      tc1 = ToolCall.new("1", "tool1", %{})
      tc2 = ToolCall.new("2", "tool2", %{})

      chunk1 = %Chunk{tool_calls: [tc1]}
      chunk2 = %Chunk{tool_calls: [tc2]}

      acc = Base.accumulate_chunk(acc, chunk1)
      acc = Base.accumulate_chunk(acc, chunk2)

      assert length(acc.tool_calls) == 2
    end
  end

  describe "build_final_response/1" do
    test "converts accumulator to Response" do
      acc = %{
        content: "Hello World",
        tool_calls: [],
        model: "gpt-4o",
        input_tokens: 10,
        output_tokens: 5,
        finish_reason: :stop
      }

      response = Base.build_final_response(acc)

      assert %Response{} = response
      assert response.content == "Hello World"
      assert response.tool_calls == nil
      assert response.model == "gpt-4o"
      assert response.total_tokens == 15
    end

    test "converts empty content to nil" do
      acc = Base.initial_accumulator()
      response = Base.build_final_response(acc)

      assert response.content == nil
    end
  end

  describe "parse_finish_reason/1" do
    test "maps common finish reasons" do
      assert Base.parse_finish_reason("stop") == :stop
      assert Base.parse_finish_reason("end_turn") == :stop
      assert Base.parse_finish_reason("length") == :length
      assert Base.parse_finish_reason("max_tokens") == :length
      assert Base.parse_finish_reason("tool_calls") == :tool_calls
      assert Base.parse_finish_reason("tool_use") == :tool_calls
      assert Base.parse_finish_reason("content_filter") == :content_filter
    end

    test "handles nil" do
      assert Base.parse_finish_reason(nil) == nil
    end

    test "converts unknown strings to atoms" do
      assert Base.parse_finish_reason("custom_reason") == :custom_reason
    end
  end

  describe "maybe_add/3" do
    test "adds value when not nil" do
      result = Base.maybe_add(%{a: 1}, :b, 2)
      assert result == %{a: 1, b: 2}
    end

    test "skips nil values" do
      result = Base.maybe_add(%{a: 1}, :b, nil)
      assert result == %{a: 1}
    end
  end

  describe "bearer_headers/1" do
    test "returns proper headers" do
      headers = Base.bearer_headers("sk-test123")

      assert {"authorization", "Bearer sk-test123"} in headers
      assert {"content-type", "application/json"} in headers
    end

    test "raises for nil API key" do
      assert_raise ArgumentError, ~r/API key is not configured/, fn ->
        Base.bearer_headers(nil)
      end
    end

    test "raises for empty API key" do
      assert_raise ArgumentError, ~r/API key is empty/, fn ->
        Base.bearer_headers("")
      end
    end
  end
end
