defmodule ElixirLLM.CircuitBreaker do
  @moduledoc """
  Circuit breaker pattern for LLM API calls.

  Prevents cascading failures by temporarily blocking requests to failing providers.

  ## States

    * `:closed` - Normal operation, requests pass through
    * `:open` - Failures exceeded threshold, requests are blocked
    * `:half_open` - Testing if service has recovered

  ## Configuration

      config :elixir_llm, :circuit_breaker,
        enabled: true,
        failure_threshold: 5,
        recovery_timeout_ms: 30_000,
        half_open_max_calls: 3

  ## Example

      # Execute with circuit breaker protection
      case ElixirLLM.CircuitBreaker.call(:openai, fn -> provider.chat(chat) end) do
        {:ok, response} -> handle_response(response)
        {:error, :circuit_open} -> handle_circuit_open()
        {:error, reason} -> handle_error(reason)
      end

      # Check circuit state
      state = ElixirLLM.CircuitBreaker.state(:openai)
  """

  use GenServer

  @table_name :elixir_llm_circuit_breaker

  @type state :: :closed | :open | :half_open
  @type provider :: atom()

  @default_failure_threshold 5
  @default_recovery_timeout_ms 30_000
  @default_half_open_max_calls 3

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the circuit breaker.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Executes a function with circuit breaker protection.

  Returns `{:error, :circuit_open}` if the circuit is open.
  """
  @spec call(provider(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def call(provider, fun) when is_function(fun, 0) do
    ensure_started()

    if enabled?() do
      do_call(provider, fun)
    else
      fun.()
    end
  end

  defp do_call(provider, fun) do
    case get_state(provider) do
      :open ->
        {:error, :circuit_open}

      :half_open ->
        # Allow limited calls in half-open state
        if can_attempt_half_open?(provider) do
          execute_and_record(provider, fun)
        else
          {:error, :circuit_open}
        end

      :closed ->
        execute_and_record(provider, fun)
    end
  end

  @doc """
  Returns the current state of the circuit for a provider.
  """
  @spec state(provider()) :: state()
  def state(provider) do
    ensure_started()
    get_state(provider)
  end

  @doc """
  Resets the circuit breaker for a provider to closed state.
  """
  @spec reset(provider()) :: :ok
  def reset(provider) do
    ensure_started()
    :ets.insert(@table_name, {provider, :closed, 0, 0, nil})
    :ok
  end

  @doc """
  Resets all circuit breakers.
  """
  @spec reset_all() :: :ok
  def reset_all do
    ensure_started()
    :ets.delete_all_objects(@table_name)
    :ok
  end

  @doc """
  Records a successful call (for external use when not using `call/2`).
  """
  @spec record_success(provider()) :: :ok
  def record_success(provider) do
    ensure_started()
    GenServer.cast(__MODULE__, {:success, provider})
  end

  @doc """
  Records a failed call (for external use when not using `call/2`).
  """
  @spec record_failure(provider()) :: :ok
  def record_failure(provider) do
    ensure_started()
    GenServer.cast(__MODULE__, {:failure, provider})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :public, :set, {:write_concurrency, true}])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_cast({:success, provider}, state) do
    handle_success(provider)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:failure, provider}, state) do
    handle_failure(provider)
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        case start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  defp enabled? do
    config = Application.get_env(:elixir_llm, :circuit_breaker, [])
    Keyword.get(config, :enabled, false)
  end

  defp get_config do
    config = Application.get_env(:elixir_llm, :circuit_breaker, [])

    %{
      failure_threshold: Keyword.get(config, :failure_threshold, @default_failure_threshold),
      recovery_timeout_ms:
        Keyword.get(config, :recovery_timeout_ms, @default_recovery_timeout_ms),
      half_open_max_calls: Keyword.get(config, :half_open_max_calls, @default_half_open_max_calls)
    }
  end

  defp get_state(provider) do
    config = get_config()

    case :ets.lookup(@table_name, provider) do
      [{^provider, :open, _failures, _half_open_calls, opened_at}] ->
        now = System.monotonic_time(:millisecond)

        if now - opened_at >= config.recovery_timeout_ms do
          # Transition to half-open
          :ets.insert(@table_name, {provider, :half_open, 0, 0, opened_at})
          :half_open
        else
          :open
        end

      [{^provider, state, _failures, _half_open_calls, _opened_at}] ->
        state

      [] ->
        :closed
    end
  end

  defp can_attempt_half_open?(provider) do
    config = get_config()

    case :ets.lookup(@table_name, provider) do
      [{^provider, :half_open, _failures, half_open_calls, _opened_at}] ->
        half_open_calls < config.half_open_max_calls

      _ ->
        true
    end
  end

  defp execute_and_record(provider, fun) do
    result = fun.()

    case result do
      {:ok, _} ->
        handle_success(provider)

      {:error, _} ->
        handle_failure(provider)
    end

    result
  end

  defp handle_success(provider) do
    case :ets.lookup(@table_name, provider) do
      [{^provider, :half_open, _failures, _half_open_calls, _opened_at}] ->
        # Success in half-open state, close the circuit
        :ets.insert(@table_name, {provider, :closed, 0, 0, nil})

      _ ->
        # Reset failure count on success
        :ets.insert(@table_name, {provider, :closed, 0, 0, nil})
    end
  end

  defp handle_failure(provider) do
    config = get_config()
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table_name, provider) do
      [{^provider, :half_open, _failures, _half_open_calls, _opened_at}] ->
        # Failure in half-open state, reopen the circuit
        :ets.insert(@table_name, {provider, :open, config.failure_threshold, 0, now})

      [{^provider, :closed, failures, _, _}] ->
        new_failures = failures + 1

        if new_failures >= config.failure_threshold do
          :ets.insert(@table_name, {provider, :open, new_failures, 0, now})
        else
          :ets.insert(@table_name, {provider, :closed, new_failures, 0, nil})
        end

      [] ->
        :ets.insert(@table_name, {provider, :closed, 1, 0, nil})
    end
  end
end
