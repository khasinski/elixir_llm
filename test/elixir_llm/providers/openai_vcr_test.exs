defmodule ElixirLLM.Providers.OpenAIVCRTest do
  use ExUnit.Case, async: false
  use ExVCR.Mock, adapter: ExVCR.Adapter.Finch

  alias ElixirLLM.{Chat, Message}
  alias ElixirLLM.Providers.OpenAI

  setup do
    # Set up API key for recording (filtered in cassettes)
    api_key = System.get_env("OPENAI_API_KEY") || "test-key"
    Application.put_env(:elixir_llm, :openai, api_key: api_key)

    on_exit(fn ->
      Application.delete_env(:elixir_llm, :openai)
    end)

    :ok
  end

  describe "chat/1" do
    test "sends a message and receives a response" do
      use_cassette "openai_chat_simple" do
        chat =
          ElixirLLM.new()
          |> ElixirLLM.model("gpt-4o-mini")
          |> Chat.add_message(Message.user("Say 'Hello from OpenAI' and nothing else."))

        {:ok, response} = OpenAI.chat(chat)

        assert response.content =~ "Hello"
        assert response.model =~ "gpt-4o-mini"
        assert is_integer(response.total_tokens)
        assert response.finish_reason == :stop
      end
    end

    test "handles system messages" do
      use_cassette "openai_chat_system" do
        chat =
          ElixirLLM.new()
          |> ElixirLLM.model("gpt-4o-mini")
          |> Chat.add_message(
            Message.system("You are a helpful assistant that only responds with 'OK'.")
          )
          |> Chat.add_message(Message.user("Hello"))

        {:ok, response} = OpenAI.chat(chat)

        assert response.content =~ "OK"
      end
    end

    test "respects temperature setting" do
      use_cassette "openai_chat_temperature" do
        chat =
          ElixirLLM.new()
          |> ElixirLLM.model("gpt-4o-mini")
          |> ElixirLLM.temperature(0.0)
          |> Chat.add_message(Message.user("What is 2+2? Reply with just the number."))

        {:ok, response} = OpenAI.chat(chat)

        assert response.content =~ "4"
      end
    end
  end

  # Note: Streaming tests are not included in VCR tests because ExVCR
  # doesn't properly capture streaming responses. Streaming is tested
  # manually or via integration tests.
end
