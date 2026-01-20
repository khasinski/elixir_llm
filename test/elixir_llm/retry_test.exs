defmodule ElixirLLM.RetryTest do
  use ExUnit.Case

  alias ElixirLLM.{Error, Retry}

  describe "with_retry/2" do
    test "returns success on first try" do
      result = Retry.with_retry(fn -> {:ok, "success"} end)
      assert {:ok, "success"} = result
    end

    test "returns error for non-retryable errors" do
      error = %Error.AuthenticationError{message: "Bad key", provider: :openai}

      result = Retry.with_retry(fn -> {:error, error} end)

      assert {:error, ^error} = result
    end

    test "retries on retryable errors" do
      counter = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(
          fn ->
            count = :counters.get(counter, 1)
            :counters.add(counter, 1, 1)

            if count < 2 do
              {:error, %{status: 500, message: "Server error"}}
            else
              {:ok, "success"}
            end
          end,
          max_attempts: 5,
          base_delay_ms: 1
        )

      assert {:ok, "success"} = result
      assert :counters.get(counter, 1) == 3
    end

    test "respects max_attempts" do
      counter = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(counter, 1, 1)
            {:error, %{status: 500}}
          end,
          max_attempts: 3,
          base_delay_ms: 1
        )

      assert {:error, _} = result
      assert :counters.get(counter, 1) == 3
    end

    test "calls on_retry callback" do
      callback_calls = :counters.new(1, [:atomics])

      Retry.with_retry(
        fn ->
          if :counters.get(callback_calls, 1) < 2 do
            {:error, %{status: 500}}
          else
            {:ok, "done"}
          end
        end,
        max_attempts: 5,
        base_delay_ms: 1,
        on_retry: fn _attempt, _error ->
          :counters.add(callback_calls, 1, 1)
        end
      )

      assert :counters.get(callback_calls, 1) == 2
    end
  end

  describe "should_retry?/1" do
    test "returns true for rate limit error struct" do
      error = %Error.RateLimitError{message: "limited", provider: :openai, retry_after: nil}
      assert Retry.should_retry?(error)
    end

    test "returns true for legacy 429 status map" do
      assert Retry.should_retry?(%{status: 429})
    end

    test "returns true for legacy 5xx status map" do
      assert Retry.should_retry?(%{status: 500})
      assert Retry.should_retry?(%{status: 502})
      assert Retry.should_retry?(%{status: 503})
    end

    test "returns true for connection errors" do
      assert Retry.should_retry?(:timeout)
      assert Retry.should_retry?(:econnrefused)
      assert Retry.should_retry?(:closed)
    end

    test "returns false for 400 errors" do
      refute Retry.should_retry?(%{status: 400})
      refute Retry.should_retry?(%{status: 401})
    end
  end

  describe "calculate_delay/2" do
    test "uses exponential backoff" do
      config = %{base_delay_ms: 1000, max_delay_ms: 30_000, jitter: false}

      assert Retry.calculate_delay(1, config) == 1000
      assert Retry.calculate_delay(2, config) == 2000
      assert Retry.calculate_delay(3, config) == 4000
      assert Retry.calculate_delay(4, config) == 8000
    end

    test "caps at max_delay_ms" do
      config = %{base_delay_ms: 1000, max_delay_ms: 5000, jitter: false}

      assert Retry.calculate_delay(1, config) == 1000
      assert Retry.calculate_delay(10, config) == 5000
    end

    test "adds jitter when enabled" do
      config = %{base_delay_ms: 1000, max_delay_ms: 30_000, jitter: true}

      delays = for _ <- 1..10, do: Retry.calculate_delay(1, config)

      # With jitter, delays should vary
      assert length(Enum.uniq(delays)) > 1
    end
  end
end
