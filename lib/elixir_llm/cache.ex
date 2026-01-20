defmodule ElixirLLM.Cache do
  @moduledoc """
  Response caching for LLM API calls.

  Caches responses based on message content and model to reduce API costs
  and improve response times for repeated queries.

  ## Configuration

      config :elixir_llm, :cache,
        enabled: true,
        ttl_ms: 3_600_000,  # 1 hour
        max_entries: 1000

  ## Example

      # Automatic caching with chat
      {:ok, response, chat} =
        ElixirLLM.new()
        |> ElixirLLM.with_cache()
        |> ElixirLLM.ask("What is 2+2?")

      # Direct cache operations
      cache_key = ElixirLLM.Cache.key(chat)
      {:ok, response} = ElixirLLM.Cache.get(cache_key)
      :ok = ElixirLLM.Cache.put(cache_key, response)

  ## Cache Key Generation

  Cache keys are generated from:
    * Model ID
    * Message history (content only, not metadata)
    * Temperature setting
    * Tool definitions (if any)
  """

  use GenServer

  @table_name :elixir_llm_cache

  @default_ttl_ms 3_600_000
  @default_max_entries 1000

  @type cache_key :: binary()

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the cache.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Generates a cache key for the given chat.
  """
  @spec key(ElixirLLM.Chat.t()) :: cache_key()
  def key(%ElixirLLM.Chat{} = chat) do
    data = %{
      model: chat.model,
      messages: Enum.map(chat.messages, &message_for_key/1),
      temperature: chat.temperature,
      tools: Enum.map(chat.tools, &tool_for_key/1)
    }

    :crypto.hash(:sha256, :erlang.term_to_binary(data))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Gets a cached response.

  Returns `{:ok, response}` if found and not expired, `:miss` otherwise.
  """
  @spec get(cache_key()) :: {:ok, ElixirLLM.Response.t()} | :miss
  def get(key) do
    ensure_started()

    if enabled?() do
      do_get(key)
    else
      :miss
    end
  end

  defp do_get(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, response, inserted_at}] ->
        ttl = get_ttl()
        now = System.monotonic_time(:millisecond)

        if now - inserted_at <= ttl do
          {:ok, response}
        else
          # Expired, remove it
          :ets.delete(@table_name, key)
          :miss
        end

      [] ->
        :miss
    end
  end

  @doc """
  Caches a response.
  """
  @spec put(cache_key(), ElixirLLM.Response.t()) :: :ok
  def put(key, response) do
    ensure_started()

    if enabled?() do
      do_put(key, response)
    else
      :ok
    end
  end

  defp do_put(key, response) do
    now = System.monotonic_time(:millisecond)
    :ets.insert(@table_name, {key, response, now})
    maybe_evict()
    :ok
  end

  @doc """
  Deletes a cached entry.
  """
  @spec delete(cache_key()) :: :ok
  def delete(key) do
    ensure_started()
    :ets.delete(@table_name, key)
    :ok
  end

  @doc """
  Clears all cached entries.
  """
  @spec clear() :: :ok
  def clear do
    ensure_started()
    :ets.delete_all_objects(@table_name)
    :ok
  end

  @doc """
  Returns the number of cached entries.
  """
  @spec size() :: non_neg_integer()
  def size do
    ensure_started()
    :ets.info(@table_name, :size)
  end

  @doc """
  Fetches a cached value or computes and caches it.

  ## Example

      ElixirLLM.Cache.fetch(cache_key, fn ->
        provider.chat(chat)
      end)
  """
  @spec fetch(cache_key(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def fetch(key, fun) when is_function(fun, 0) do
    case get(key) do
      {:ok, response} ->
        {:ok, response}

      :miss ->
        case fun.() do
          {:ok, response} = result ->
            put(key, response)
            result

          error ->
            error
        end
    end
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :public, :set, {:write_concurrency, true}])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
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
    config = Application.get_env(:elixir_llm, :cache, [])
    Keyword.get(config, :enabled, false)
  end

  defp get_ttl do
    config = Application.get_env(:elixir_llm, :cache, [])
    Keyword.get(config, :ttl_ms, @default_ttl_ms)
  end

  defp get_max_entries do
    config = Application.get_env(:elixir_llm, :cache, [])
    Keyword.get(config, :max_entries, @default_max_entries)
  end

  defp message_for_key(%{role: role, content: content}) do
    {role, content}
  end

  defp tool_for_key(tool) when is_atom(tool) do
    tool.name()
  end

  defp tool_for_key(%{name: name}) do
    name
  end

  defp maybe_evict do
    max_entries = get_max_entries()
    current_size = :ets.info(@table_name, :size)

    if current_size > max_entries do
      # Evict oldest entries (FIFO)
      to_evict = current_size - max_entries + div(max_entries, 10)
      evict_oldest(to_evict)
    end
  end

  defp evict_oldest(count) do
    entries =
      :ets.tab2list(@table_name)
      |> Enum.sort_by(fn {_key, _response, inserted_at} -> inserted_at end)
      |> Enum.take(count)

    Enum.each(entries, fn {key, _, _} ->
      :ets.delete(@table_name, key)
    end)
  end

  defp cleanup_expired do
    ttl = get_ttl()
    now = System.monotonic_time(:millisecond)
    cutoff = now - ttl

    :ets.select_delete(@table_name, [
      {{:"$1", :"$2", :"$3"}, [{:<, :"$3", cutoff}], [true]}
    ])
  end

  defp schedule_cleanup do
    # Run cleanup every minute
    Process.send_after(self(), :cleanup, 60_000)
  end
end
