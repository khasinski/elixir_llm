defmodule ElixirLLMTest do
  use ExUnit.Case

  alias ElixirLLM.{Chat, Chunk, Message, Response, Tool, ToolCall}

  describe "new/1" do
    test "creates a new chat" do
      chat = ElixirLLM.new()
      assert %Chat{} = chat
      assert chat.messages == []
      assert chat.tools == []
    end

    test "creates a chat with model" do
      chat = ElixirLLM.new(model: "gpt-4o")
      assert chat.model == "gpt-4o"
      assert chat.provider == ElixirLLM.Providers.OpenAI
    end

    test "auto-detects provider from model" do
      assert ElixirLLM.new(model: "gpt-4o").provider == ElixirLLM.Providers.OpenAI
      assert ElixirLLM.new(model: "claude-sonnet-4-5").provider == ElixirLLM.Providers.Anthropic
      assert ElixirLLM.new(model: "llama3.2").provider == ElixirLLM.Providers.Ollama
    end
  end

  describe "pipe-based API" do
    test "model/2 sets the model" do
      chat =
        ElixirLLM.new()
        |> ElixirLLM.model("claude-sonnet-4-5")

      assert chat.model == "claude-sonnet-4-5"
    end

    test "temperature/2 sets temperature" do
      chat =
        ElixirLLM.new()
        |> ElixirLLM.temperature(0.7)

      assert chat.temperature == 0.7
    end

    test "instructions/2 adds system message" do
      chat =
        ElixirLLM.new()
        |> ElixirLLM.instructions("You are helpful")

      assert [%Message{role: :system, content: "You are helpful"}] = chat.messages
    end

    test "tool/2 registers a tool" do
      tool =
        Tool.define(
          name: "test",
          description: "A test tool",
          parameters: %{},
          execute: fn _ -> {:ok, "done"} end
        )

      chat =
        ElixirLLM.new()
        |> ElixirLLM.tool(tool)

      assert length(chat.tools) == 1
    end
  end

  describe "Message" do
    test "creates user message" do
      msg = Message.user("Hello")
      assert msg.role == :user
      assert msg.content == "Hello"
    end

    test "creates assistant message" do
      msg = Message.assistant("Hi there")
      assert msg.role == :assistant
      assert msg.content == "Hi there"
    end

    test "creates system message" do
      msg = Message.system("Be helpful")
      assert msg.role == :system
      assert msg.content == "Be helpful"
    end

    test "creates tool result message" do
      msg = Message.tool_result("call_123", "42")
      assert msg.role == :tool
      assert msg.content == "42"
      assert msg.tool_call_id == "call_123"
    end
  end

  describe "ToolCall" do
    test "creates a tool call" do
      tc = ToolCall.new("id_123", "calculator", %{expression: "2+2"})
      assert tc.id == "id_123"
      assert tc.name == "calculator"
      assert tc.arguments == %{expression: "2+2"}
    end
  end

  describe "Response" do
    test "has_tool_calls?/1 returns false for nil" do
      response = Response.new(content: "Hello", tool_calls: nil)
      refute Response.has_tool_calls?(response)
    end

    test "has_tool_calls?/1 returns false for empty list" do
      response = Response.new(content: "Hello", tool_calls: [])
      refute Response.has_tool_calls?(response)
    end

    test "has_tool_calls?/1 returns true for non-empty list" do
      tc = ToolCall.new("id", "test", %{})
      response = Response.new(content: nil, tool_calls: [tc])
      assert Response.has_tool_calls?(response)
    end
  end

  describe "Chunk" do
    test "final?/1 returns false for nil finish_reason" do
      chunk = Chunk.new(content: "Hello")
      refute Chunk.final?(chunk)
    end

    test "final?/1 returns true for non-nil finish_reason" do
      chunk = Chunk.new(content: "Hello", finish_reason: :stop)
      assert Chunk.final?(chunk)
    end
  end

  describe "Tool" do
    test "define/1 creates inline tool" do
      tool =
        Tool.define(
          name: "calc",
          description: "Calculator",
          parameters: %{
            expr: [type: :string, required: true]
          },
          execute: fn %{expr: _} -> {:ok, 42} end
        )

      assert tool.name == "calc"
      assert tool.description == "Calculator"
      assert is_function(tool.execute, 1)
    end

    test "execute/2 works with inline tools" do
      tool =
        Tool.define(
          name: "calc",
          description: "Calculator",
          parameters: %{},
          execute: fn _ -> {:ok, 42} end
        )

      assert {:ok, 42} = Tool.execute(tool, %{})
    end

    test "normalizes string keys to atoms" do
      tool =
        Tool.define(
          name: "test",
          description: "Test",
          parameters: %{},
          execute: fn %{foo: val} -> {:ok, val} end
        )

      assert {:ok, "bar"} = Tool.execute(tool, %{"foo" => "bar"})
    end
  end

  describe "Config" do
    test "provider_for_model/1 detects OpenAI models" do
      assert ElixirLLM.Config.provider_for_model("gpt-4o") == ElixirLLM.Providers.OpenAI
      assert ElixirLLM.Config.provider_for_model("gpt-4-turbo") == ElixirLLM.Providers.OpenAI
      assert ElixirLLM.Config.provider_for_model("o1-preview") == ElixirLLM.Providers.OpenAI
    end

    test "provider_for_model/1 detects Anthropic models" do
      assert ElixirLLM.Config.provider_for_model("claude-3-opus") == ElixirLLM.Providers.Anthropic

      assert ElixirLLM.Config.provider_for_model("claude-sonnet-4-5") ==
               ElixirLLM.Providers.Anthropic
    end

    test "provider_for_model/1 detects Ollama models" do
      assert ElixirLLM.Config.provider_for_model("llama3.2") == ElixirLLM.Providers.Ollama
    end

    test "provider_for_model/1 detects OpenRouter models" do
      assert ElixirLLM.Config.provider_for_model("openrouter/openai/gpt-4o") ==
               ElixirLLM.Providers.OpenRouter

      assert ElixirLLM.Config.provider_for_model("openrouter/anthropic/claude-3.5-sonnet") ==
               ElixirLLM.Providers.OpenRouter
    end

    test "provider_for_model/1 detects Gemini models" do
      assert ElixirLLM.Config.provider_for_model("gemini-2.0-flash") ==
               ElixirLLM.Providers.Gemini

      assert ElixirLLM.Config.provider_for_model("gemini-1.5-pro") ==
               ElixirLLM.Providers.Gemini
    end

    test "provider_for_model/1 detects Groq models" do
      assert ElixirLLM.Config.provider_for_model("groq/llama-3.3-70b-versatile") ==
               ElixirLLM.Providers.Groq
    end

    test "provider_for_model/1 detects Mistral API models" do
      assert ElixirLLM.Config.provider_for_model("mistral-api/mistral-large-latest") ==
               ElixirLLM.Providers.Mistral

      assert ElixirLLM.Config.provider_for_model("mistral-large-latest") ==
               ElixirLLM.Providers.Mistral

      assert ElixirLLM.Config.provider_for_model("codestral-latest") ==
               ElixirLLM.Providers.Mistral
    end

    test "provider_for_model/1 detects Together AI models" do
      assert ElixirLLM.Config.provider_for_model("together/meta-llama/Llama-3.3-70B") ==
               ElixirLLM.Providers.Together
    end
  end

  describe "Content" do
    test "media_type_from_path handles common image types" do
      content = ElixirLLM.Content.image("test.jpg")
      assert content.media_type == "image/jpeg"

      content = ElixirLLM.Content.image("test.png")
      assert content.media_type == "image/png"

      content = ElixirLLM.Content.image("test.webp")
      assert content.media_type == "image/webp"
    end

    test "media_type_from_path handles audio types" do
      content = ElixirLLM.Content.audio("test.mp3")
      assert content.media_type == "audio/mpeg"

      content = ElixirLLM.Content.audio("test.wav")
      assert content.media_type == "audio/wav"
    end

    test "media_type_from_path returns default for unknown types" do
      content = ElixirLLM.Content.file("test.xyz")
      assert content.media_type == "application/octet-stream"
    end
  end
end
