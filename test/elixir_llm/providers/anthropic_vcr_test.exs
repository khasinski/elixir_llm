defmodule ElixirLLM.Providers.AnthropicVCRTest do
  use ExUnit.Case, async: false
  use ExVCR.Mock, adapter: ExVCR.Adapter.Finch

  alias ElixirLLM.{Chat, Message}
  alias ElixirLLM.Providers.Anthropic

  setup do
    # Set up API key for recording (filtered in cassettes)
    api_key = System.get_env("ANTHROPIC_API_KEY") || "test-key"
    Application.put_env(:elixir_llm, :anthropic, api_key: api_key)

    on_exit(fn ->
      Application.delete_env(:elixir_llm, :anthropic)
    end)

    :ok
  end

  describe "chat/1" do
    test "sends a message and receives a response" do
      use_cassette "anthropic_chat_simple" do
        chat =
          ElixirLLM.new()
          |> ElixirLLM.model("claude-3-5-haiku-latest")
          |> Chat.add_message(Message.user("Say 'Hello from Claude' and nothing else."))

        {:ok, response} = Anthropic.chat(chat)

        assert response.content =~ "Hello"
        assert response.model =~ "claude"
        assert is_integer(response.total_tokens)
        assert response.finish_reason == :stop
      end
    end

    test "handles system messages" do
      use_cassette "anthropic_chat_system" do
        chat =
          ElixirLLM.new()
          |> ElixirLLM.model("claude-3-5-haiku-latest")
          |> Chat.add_message(
            Message.system("You are a helpful assistant that only responds with 'OK'.")
          )
          |> Chat.add_message(Message.user("Hello"))

        {:ok, response} = Anthropic.chat(chat)

        assert response.content =~ "OK"
      end
    end

    test "respects max_tokens setting" do
      use_cassette "anthropic_chat_max_tokens" do
        chat =
          ElixirLLM.new()
          |> ElixirLLM.model("claude-3-5-haiku-latest")
          |> ElixirLLM.max_tokens(50)
          |> Chat.add_message(Message.user("What is the capital of France? Reply briefly."))

        {:ok, response} = Anthropic.chat(chat)

        assert response.content =~ "Paris"
        assert response.output_tokens <= 50
      end
    end
  end

  # Note: Streaming tests are not included in VCR tests because ExVCR
  # doesn't properly capture streaming responses. Streaming is tested
  # manually or via integration tests.
end
