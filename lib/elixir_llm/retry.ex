defmodule ElixirLLM.Retry do
  @moduledoc """
  Retry mechanism with exponential backoff for LLM API calls.

  ## Configuration

      config :elixir_llm, :retry,
        max_attempts: 3,
        base_delay_ms: 1000,
        max_delay_ms: 30_000,
        jitter: true

  ## Example

      # With default retry settings
      ElixirLLM.new()
      |> ElixirLLM.with_retry()
      |> ElixirLLM.ask("Hello!")

      # With custom retry settings
      ElixirLLM.new()
      |> ElixirLLM.with_retry(max_attempts: 5, base_delay_ms: 500)
      |> ElixirLLM.ask("Hello!")

  ## Retry Behavior

  By default, the following errors are retried:
    * Rate limit errors (429)
    * Server errors (5xx)
    * Network errors
    * Timeout errors

  Non-retryable errors (authentication, validation) are returned immediately.
  """

  alias ElixirLLM.Error

  @type retry_opts :: [
          max_attempts: pos_integer(),
          base_delay_ms: pos_integer(),
          max_delay_ms: pos_integer(),
          jitter: boolean(),
          on_retry: (integer(), term() -> any())
        ]

  @default_max_attempts 3
  @default_base_delay_ms 1000
  @default_max_delay_ms 30_000
  @default_jitter true

  @doc """
  Executes a function with retry logic.

  ## Options

    * `:max_attempts` - Maximum number of attempts (default: 3)
    * `:base_delay_ms` - Base delay between retries in milliseconds (default: 1000)
    * `:max_delay_ms` - Maximum delay between retries (default: 30000)
    * `:jitter` - Add random jitter to delays (default: true)
    * `:on_retry` - Callback called before each retry: `(attempt, error) -> any()`

  ## Example

      ElixirLLM.Retry.with_retry(fn ->
        provider.chat(chat)
      end, max_attempts: 5)
  """
  @spec with_retry((-> {:ok, term()} | {:error, term()}), retry_opts()) ::
          {:ok, term()} | {:error, term()}
  def with_retry(fun, opts \\ []) when is_function(fun, 0) do
    config = get_config(opts)
    do_retry(fun, config, 1)
  end

  defp do_retry(fun, config, attempt) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, error} ->
        if should_retry?(error) and attempt < config.max_attempts do
          delay = calculate_delay(attempt, config)

          # Call on_retry callback if provided
          if config.on_retry do
            config.on_retry.(attempt, error)
          end

          Process.sleep(delay)
          do_retry(fun, config, attempt + 1)
        else
          {:error, error}
        end
    end
  end

  @doc """
  Returns true if the error should trigger a retry.
  """
  @spec should_retry?(term()) :: boolean()
  def should_retry?(%Error.RateLimitError{}), do: true
  def should_retry?(%Error.NetworkError{}), do: true
  def should_retry?(%Error.TimeoutError{}), do: true
  def should_retry?(%Error.ProviderError{}), do: true
  def should_retry?(%Error.APIError{status: status}) when is_integer(status) and status in 500..599, do: true
  def should_retry?(%Error.APIError{status: 429}), do: true

  # For legacy error maps (before structured errors are used everywhere)
  def should_retry?(%{status: 429}), do: true
  def should_retry?(%{status: status}) when status in 500..599, do: true
  def should_retry?(:timeout), do: true
  def should_retry?(:econnrefused), do: true
  def should_retry?(:closed), do: true

  def should_retry?(_), do: false

  @doc """
  Calculates the delay for a given retry attempt using exponential backoff.
  """
  @spec calculate_delay(pos_integer(), map()) :: non_neg_integer()
  def calculate_delay(attempt, config) do
    # Exponential backoff: base_delay * 2^(attempt - 1)
    delay = config.base_delay_ms * :math.pow(2, attempt - 1)
    delay = min(round(delay), config.max_delay_ms)

    if config.jitter do
      add_jitter(delay)
    else
      delay
    end
  end

  defp add_jitter(delay) do
    # Add +/- 25% jitter
    jitter_range = round(delay * 0.25)
    delay + :rand.uniform(jitter_range * 2 + 1) - jitter_range - 1
  end

  defp get_config(opts) do
    app_config = Application.get_env(:elixir_llm, :retry, [])

    %{
      max_attempts:
        Keyword.get(opts, :max_attempts, Keyword.get(app_config, :max_attempts, @default_max_attempts)),
      base_delay_ms:
        Keyword.get(opts, :base_delay_ms, Keyword.get(app_config, :base_delay_ms, @default_base_delay_ms)),
      max_delay_ms:
        Keyword.get(opts, :max_delay_ms, Keyword.get(app_config, :max_delay_ms, @default_max_delay_ms)),
      jitter: Keyword.get(opts, :jitter, Keyword.get(app_config, :jitter, @default_jitter)),
      on_retry: Keyword.get(opts, :on_retry)
    }
  end
end
