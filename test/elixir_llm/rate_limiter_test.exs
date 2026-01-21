defmodule ElixirLLM.RateLimiterTest do
  use ExUnit.Case, async: false

  alias ElixirLLM.RateLimiter

  setup do
    # Ensure rate limiter is started fresh
    case Process.whereis(RateLimiter) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal, 100)
    end

    # Small delay to ensure cleanup
    Process.sleep(10)

    # Start fresh
    {:ok, _pid} = RateLimiter.start_link()
    :ok
  end

  describe "try_acquire/1" do
    test "returns :ok when tokens are available" do
      assert :ok = RateLimiter.try_acquire(:test_provider)
    end

    test "returns {:error, :rate_limited} when tokens exhausted" do
      # Acquire all tokens rapidly
      for _ <- 1..100 do
        RateLimiter.try_acquire(:exhausted_provider)
      end

      # Should eventually get rate limited
      results = for _ <- 1..10, do: RateLimiter.try_acquire(:exhausted_provider)
      assert {:error, :rate_limited} in results
    end
  end

  describe "acquire/2" do
    test "returns :ok immediately when tokens available" do
      assert :ok = RateLimiter.acquire(:test_acquire, 1000)
    end
  end

  describe "available/1" do
    test "returns positive number for new provider" do
      assert RateLimiter.available(:new_provider) > 0
    end

    test "decreases after acquiring tokens" do
      initial = RateLimiter.available(:decrement_test)
      :ok = RateLimiter.try_acquire(:decrement_test)
      after_acquire = RateLimiter.available(:decrement_test)

      assert after_acquire < initial
    end
  end

  describe "reset/1" do
    test "restores tokens after depletion" do
      provider = :reset_test

      # Deplete tokens
      for _ <- 1..100, do: RateLimiter.try_acquire(provider)

      # Reset should restore tokens
      :ok = RateLimiter.reset(provider)
      after_reset = RateLimiter.available(provider)

      assert after_reset > 0
    end
  end

  describe "reset_all/0" do
    test "resets all provider buckets" do
      # Use tokens on multiple providers
      RateLimiter.try_acquire(:provider_a)
      RateLimiter.try_acquire(:provider_b)

      # Reset all
      :ok = RateLimiter.reset_all()

      # Both should have full buckets
      assert RateLimiter.available(:provider_a) > 0
      assert RateLimiter.available(:provider_b) > 0
    end
  end
end
