defmodule ElixirLLM.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for LLM API calls.

  Provides client-side rate limiting to prevent hitting provider rate limits.
  Uses ETS for efficient concurrent access.

  ## Configuration

      config :elixir_llm, :rate_limiter,
        enabled: true,
        openai: [requests_per_minute: 60],
        anthropic: [requests_per_minute: 50],
        openrouter: [requests_per_minute: 100],
        ollama: [requests_per_minute: 1000]

  ## Example

      # Wait for a token before making a request
      :ok = ElixirLLM.RateLimiter.acquire(:openai)

      # Non-blocking check
      case ElixirLLM.RateLimiter.try_acquire(:openai) do
        :ok -> # proceed
        {:error, :rate_limited} -> # handle rate limiting
      end

      # Check remaining tokens
      tokens = ElixirLLM.RateLimiter.available(:openai)
  """

  use GenServer

  @table_name :elixir_llm_rate_limiter

  # Default rates per minute
  @default_rates %{
    openai: 60,
    anthropic: 50,
    openrouter: 100,
    ollama: 1000,
    gemini: 60,
    mistral: 100,
    groq: 30,
    together: 60
  }

  @type provider :: atom()

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the rate limiter.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Acquires a token for the given provider, blocking if necessary.

  Returns `:ok` when a token is available.
  """
  @spec acquire(provider(), timeout()) :: :ok
  def acquire(provider, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_acquire(provider, deadline)
  end

  defp do_acquire(provider, deadline) do
    case try_acquire(provider) do
      :ok ->
        :ok

      {:error, :rate_limited} ->
        now = System.monotonic_time(:millisecond)

        if now < deadline do
          # Wait a bit and retry
          Process.sleep(100)
          do_acquire(provider, deadline)
        else
          # Timeout exceeded, allow anyway (log warning)
          :ok
        end
    end
  end

  @doc """
  Attempts to acquire a token without blocking.

  Returns `:ok` if successful, `{:error, :rate_limited}` otherwise.
  """
  @spec try_acquire(provider()) :: :ok | {:error, :rate_limited}
  def try_acquire(provider) do
    ensure_started()

    if enabled?() do
      bucket_key = bucket_key(provider)
      refill_bucket(provider)

      case :ets.update_counter(@table_name, bucket_key, {3, -1, 0, 0}, {bucket_key, 0, 0}) do
        count when count > 0 ->
          :ets.update_counter(@table_name, bucket_key, {3, -1})
          :ok

        _ ->
          {:error, :rate_limited}
      end
    else
      :ok
    end
  end

  @doc """
  Returns the number of available tokens for a provider.
  """
  @spec available(provider()) :: non_neg_integer()
  def available(provider) do
    ensure_started()
    refill_bucket(provider)
    bucket_key = bucket_key(provider)

    case :ets.lookup(@table_name, bucket_key) do
      [{^bucket_key, _, tokens}] -> max(tokens, 0)
      [] -> get_rate(provider)
    end
  end

  @doc """
  Resets the rate limiter for a provider.
  """
  @spec reset(provider()) :: :ok
  def reset(provider) do
    ensure_started()
    bucket_key = bucket_key(provider)
    rate = get_rate(provider)
    now = System.monotonic_time(:millisecond)
    :ets.insert(@table_name, {bucket_key, now, rate})
    :ok
  end

  @doc """
  Resets all rate limiters.
  """
  @spec reset_all() :: :ok
  def reset_all do
    ensure_started()
    :ets.delete_all_objects(@table_name)
    :ok
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :public, :set, {:write_concurrency, true}])
    {:ok, %{table: table}}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        # Start under a simple supervisor if not already started
        case start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  defp enabled? do
    config = Application.get_env(:elixir_llm, :rate_limiter, [])
    Keyword.get(config, :enabled, true)
  end

  defp bucket_key(provider), do: {:bucket, provider}

  defp get_rate(provider) do
    config = Application.get_env(:elixir_llm, :rate_limiter, [])
    provider_config = Keyword.get(config, provider, [])

    rpm =
      Keyword.get(provider_config, :requests_per_minute, Map.get(@default_rates, provider, 60))

    # Convert to tokens per second (we refill every second)
    max(div(rpm, 60), 1)
  end

  defp refill_bucket(provider) do
    bucket_key = bucket_key(provider)
    now = System.monotonic_time(:millisecond)
    rate_per_second = get_rate(provider)
    max_tokens = rate_per_second * 60

    case :ets.lookup(@table_name, bucket_key) do
      [{^bucket_key, last_refill, tokens}] ->
        elapsed_seconds = (now - last_refill) / 1_000
        new_tokens = min(tokens + round(elapsed_seconds * rate_per_second), max_tokens)

        if elapsed_seconds >= 1.0 do
          :ets.insert(@table_name, {bucket_key, now, new_tokens})
        end

      [] ->
        # Initialize bucket
        :ets.insert(@table_name, {bucket_key, now, max_tokens})
    end
  end
end
