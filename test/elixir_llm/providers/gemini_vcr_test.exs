defmodule ElixirLLM.Providers.GeminiVCRTest do
  use ExUnit.Case, async: false
  use ExVCR.Mock, adapter: ExVCR.Adapter.Finch

  alias ElixirLLM.{Chat, Message}
  alias ElixirLLM.Providers.Gemini

  setup do
    # Set up API key for recording (filtered in cassettes)
    api_key = System.get_env("GOOGLE_API_KEY") || "test-key"
    Application.put_env(:elixir_llm, :gemini, api_key: api_key)

    on_exit(fn ->
      Application.delete_env(:elixir_llm, :gemini)
    end)

    :ok
  end

  describe "chat/1" do
    test "sends a message and receives a response with flash model" do
      use_cassette "gemini_chat_flash" do
        chat =
          ElixirLLM.new()
          |> ElixirLLM.model("gemini-2.0-flash")
          |> Chat.add_message(Message.user("Say 'Hello from Gemini' and nothing else."))

        {:ok, response} = Gemini.chat(chat)

        assert response.content =~ "Hello"
        assert response.model =~ "gemini"
        assert is_integer(response.total_tokens)
        assert response.finish_reason == :stop
      end
    end

    test "sends a message with flash-lite (nano) model" do
      use_cassette "gemini_chat_nano" do
        chat =
          ElixirLLM.new()
          |> ElixirLLM.model("gemini-2.0-flash-lite")
          |> Chat.add_message(Message.user("Say 'Hello from Nano' and nothing else."))

        {:ok, response} = Gemini.chat(chat)

        assert response.content =~ "Hello"
        assert response.model =~ "gemini"
      end
    end

    test "handles system messages" do
      use_cassette "gemini_chat_system" do
        chat =
          ElixirLLM.new()
          |> ElixirLLM.model("gemini-2.0-flash-lite")
          |> Chat.add_message(Message.system("You are a helpful assistant that only responds with 'OK'."))
          |> Chat.add_message(Message.user("Hello"))

        {:ok, response} = Gemini.chat(chat)

        assert response.content =~ "OK"
      end
    end

    test "respects temperature setting" do
      use_cassette "gemini_chat_temperature" do
        chat =
          ElixirLLM.new()
          |> ElixirLLM.model("gemini-2.0-flash-lite")
          |> ElixirLLM.temperature(0.0)
          |> Chat.add_message(Message.user("What is 2+2? Reply with just the number."))

        {:ok, response} = Gemini.chat(chat)

        assert response.content =~ "4"
      end
    end
  end

  # Note: Streaming tests are not included in VCR tests because ExVCR
  # doesn't properly capture streaming responses. Streaming is tested
  # manually or via integration tests.
end
