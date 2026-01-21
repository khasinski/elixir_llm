defmodule ElixirLLM.CircuitBreakerTest do
  use ExUnit.Case, async: false

  alias ElixirLLM.CircuitBreaker

  setup do
    # Enable circuit breaker and reset before each test
    Application.put_env(:elixir_llm, :circuit_breaker,
      enabled: true,
      failure_threshold: 3,
      recovery_timeout_ms: 100,
      half_open_max_calls: 2
    )

    CircuitBreaker.reset_all()
    :ok
  end

  describe "state/1" do
    test "returns :closed for new provider" do
      assert CircuitBreaker.state(:new_provider) == :closed
    end
  end

  describe "call/2" do
    test "executes function when circuit is closed" do
      result = CircuitBreaker.call(:test_provider, fn -> {:ok, "success"} end)
      assert result == {:ok, "success"}
    end

    test "returns function result on success" do
      result = CircuitBreaker.call(:success_test, fn -> {:ok, %{data: 123}} end)
      assert result == {:ok, %{data: 123}}
    end

    test "returns function error on failure" do
      result = CircuitBreaker.call(:error_test, fn -> {:error, :some_error} end)
      assert result == {:error, :some_error}
    end

    test "opens circuit after threshold failures" do
      provider = :threshold_test

      # Cause failures to reach threshold (3)
      for _ <- 1..3 do
        CircuitBreaker.call(provider, fn -> {:error, :fail} end)
      end

      # Circuit should be open now
      assert CircuitBreaker.state(provider) == :open

      # Calls should be rejected
      result = CircuitBreaker.call(provider, fn -> {:ok, "should not run"} end)
      assert result == {:error, :circuit_open}
    end

    test "transitions to half-open after recovery timeout" do
      provider = :recovery_test

      # Open the circuit
      for _ <- 1..3 do
        CircuitBreaker.call(provider, fn -> {:error, :fail} end)
      end

      assert CircuitBreaker.state(provider) == :open

      # Wait for recovery timeout
      Process.sleep(150)

      # Should be half-open now
      assert CircuitBreaker.state(provider) == :half_open
    end

    test "closes circuit on success in half-open state" do
      provider = :close_test

      # Open the circuit
      for _ <- 1..3 do
        CircuitBreaker.call(provider, fn -> {:error, :fail} end)
      end

      # Wait for half-open
      Process.sleep(150)
      assert CircuitBreaker.state(provider) == :half_open

      # Success should close it
      CircuitBreaker.call(provider, fn -> {:ok, "success"} end)
      assert CircuitBreaker.state(provider) == :closed
    end

    test "reopens circuit on failure in half-open state" do
      provider = :reopen_test

      # Open the circuit
      for _ <- 1..3 do
        CircuitBreaker.call(provider, fn -> {:error, :fail} end)
      end

      # Wait for half-open
      Process.sleep(150)
      assert CircuitBreaker.state(provider) == :half_open

      # Failure should reopen it
      CircuitBreaker.call(provider, fn -> {:error, :fail} end)
      assert CircuitBreaker.state(provider) == :open
    end
  end

  describe "reset/1" do
    test "resets circuit to closed state" do
      provider = :reset_test

      # Open the circuit
      for _ <- 1..3 do
        CircuitBreaker.call(provider, fn -> {:error, :fail} end)
      end

      assert CircuitBreaker.state(provider) == :open

      # Reset
      :ok = CircuitBreaker.reset(provider)
      assert CircuitBreaker.state(provider) == :closed
    end
  end

  describe "record_success/1 and record_failure/1" do
    test "record_failure increments failure count" do
      provider = :manual_record

      for _ <- 1..3 do
        CircuitBreaker.record_failure(provider)
      end

      # Allow async cast to complete
      Process.sleep(10)

      assert CircuitBreaker.state(provider) == :open
    end

    test "record_success resets failure count" do
      provider = :manual_success

      CircuitBreaker.record_failure(provider)
      CircuitBreaker.record_failure(provider)
      CircuitBreaker.record_success(provider)

      # Allow async casts to complete
      Process.sleep(10)

      assert CircuitBreaker.state(provider) == :closed
    end
  end
end
