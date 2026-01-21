defmodule ElixirLLM.CacheTest do
  use ExUnit.Case, async: false

  alias ElixirLLM.{Cache, Chat, Message, Response}

  setup do
    # Enable cache and clear before each test
    Application.put_env(:elixir_llm, :cache,
      enabled: true,
      ttl_ms: 1000,
      max_entries: 10
    )

    Cache.clear()
    :ok
  end

  describe "key/1" do
    test "generates consistent key for same chat" do
      chat =
        Chat.new()
        |> Map.put(:model, "gpt-4o")
        |> Map.put(:messages, [Message.user("Hello")])

      key1 = Cache.key(chat)
      key2 = Cache.key(chat)

      assert key1 == key2
      assert is_binary(key1)
      assert byte_size(key1) == 64
    end

    test "generates different keys for different messages" do
      chat1 =
        Chat.new()
        |> Map.put(:model, "gpt-4o")
        |> Map.put(:messages, [Message.user("Hello")])

      chat2 =
        Chat.new()
        |> Map.put(:model, "gpt-4o")
        |> Map.put(:messages, [Message.user("Goodbye")])

      assert Cache.key(chat1) != Cache.key(chat2)
    end

    test "generates different keys for different models" do
      chat1 =
        Chat.new()
        |> Map.put(:model, "gpt-4o")
        |> Map.put(:messages, [Message.user("Hello")])

      chat2 =
        Chat.new()
        |> Map.put(:model, "claude-3-opus")
        |> Map.put(:messages, [Message.user("Hello")])

      assert Cache.key(chat1) != Cache.key(chat2)
    end
  end

  describe "put/2 and get/1" do
    test "stores and retrieves response" do
      response = Response.new(content: "Hello world", model: "gpt-4o")
      key = "test_key_1"

      :ok = Cache.put(key, response)
      assert {:ok, ^response} = Cache.get(key)
    end

    test "returns :miss for non-existent key" do
      assert :miss = Cache.get("nonexistent_key")
    end

    test "returns :miss for expired entry" do
      response = Response.new(content: "Hello", model: "gpt-4o")
      key = "expiring_key"

      :ok = Cache.put(key, response)
      assert {:ok, ^response} = Cache.get(key)

      # Wait for TTL to expire (configured as 1000ms)
      Process.sleep(1100)

      assert :miss = Cache.get(key)
    end
  end

  describe "delete/1" do
    test "removes cached entry" do
      response = Response.new(content: "Delete me", model: "gpt-4o")
      key = "delete_key"

      Cache.put(key, response)
      assert {:ok, _} = Cache.get(key)

      :ok = Cache.delete(key)
      assert :miss = Cache.get(key)
    end
  end

  describe "clear/0" do
    test "removes all cached entries" do
      for i <- 1..5 do
        Cache.put("key_#{i}", Response.new(content: "value_#{i}"))
      end

      assert Cache.size() == 5

      :ok = Cache.clear()

      assert Cache.size() == 0
    end
  end

  describe "size/0" do
    test "returns 0 for empty cache" do
      Cache.clear()
      assert Cache.size() == 0
    end

    test "returns correct count after puts" do
      Cache.clear()

      Cache.put("a", Response.new(content: "a"))
      Cache.put("b", Response.new(content: "b"))
      Cache.put("c", Response.new(content: "c"))

      assert Cache.size() == 3
    end
  end

  describe "fetch/2" do
    test "returns cached value without executing function" do
      key = "fetch_cached"
      response = Response.new(content: "cached", model: "gpt-4o")
      Cache.put(key, response)

      # Function should not be called
      result =
        Cache.fetch(key, fn ->
          raise "Should not be called"
        end)

      assert result == {:ok, response}
    end

    test "executes function and caches result on miss" do
      key = "fetch_miss"
      response = Response.new(content: "computed", model: "gpt-4o")

      result = Cache.fetch(key, fn -> {:ok, response} end)

      assert result == {:ok, response}
      assert {:ok, ^response} = Cache.get(key)
    end

    test "does not cache errors" do
      key = "fetch_error"

      result = Cache.fetch(key, fn -> {:error, :some_error} end)

      assert result == {:error, :some_error}
      assert :miss = Cache.get(key)
    end
  end

  describe "eviction" do
    test "evicts oldest entries when max_entries exceeded" do
      # Configure small cache
      Application.put_env(:elixir_llm, :cache, enabled: true, max_entries: 5, ttl_ms: 60_000)
      Cache.clear()

      # Add more than max entries
      for i <- 1..8 do
        Cache.put("evict_#{i}", Response.new(content: "value_#{i}"))
        Process.sleep(10)
      end

      # Cache should have evicted some entries
      assert Cache.size() <= 6
    end
  end
end
