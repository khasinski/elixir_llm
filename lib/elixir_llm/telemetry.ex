defmodule ElixirLLM.Telemetry do
  @moduledoc """
  Telemetry integration for ElixirLLM.

  ElixirLLM emits the following telemetry events:

  ## Chat Events

  - `[:elixir_llm, :chat, :start]` - Emitted when a chat request starts
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{provider: atom, model: string}`

  - `[:elixir_llm, :chat, :stop]` - Emitted when a chat request completes
    - Measurements: `%{duration: integer}`
    - Metadata: `%{provider: atom, model: string}`

  - `[:elixir_llm, :chat, :complete]` - Emitted with token usage
    - Measurements: `%{duration: integer, tokens: integer}`
    - Metadata: `%{provider: atom, model: string}`

  - `[:elixir_llm, :chat, :error]` - Emitted on chat error
    - Measurements: `%{}`
    - Metadata: `%{provider: atom, model: string, error: term}`

  ## Streaming Events

  - `[:elixir_llm, :stream, :start]` - Emitted when streaming starts
  - `[:elixir_llm, :stream, :stop]` - Emitted when streaming completes
  - `[:elixir_llm, :stream, :chunk]` - Emitted for each chunk
  - `[:elixir_llm, :stream, :error]` - Emitted on streaming error

  ## Tool Events

  - `[:elixir_llm, :tool, :call]` - Emitted when a tool is called
    - Measurements: `%{}`
    - Metadata: `%{tool_name: string, arguments: map}`

  - `[:elixir_llm, :tool, :result]` - Emitted when a tool returns
    - Measurements: `%{duration: integer}`
    - Metadata: `%{tool_name: string, result: term}`

  ## Tool Batch Events (Parallel Execution)

  - `[:elixir_llm, :tool_batch, :start]` - Emitted when a batch of tools starts executing
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{tool_count: integer, max_concurrency: integer, parallel: boolean}`

  - `[:elixir_llm, :tool_batch, :stop]` - Emitted when a batch of tools completes
    - Measurements: `%{duration: integer}`
    - Metadata: `%{success_count: integer, error_count: integer, timeout_count: integer}`

  ## Example Usage

      :telemetry.attach(
        "elixir-llm-logger",
        [:elixir_llm, :chat, :complete],
        fn event, measurements, metadata, _config ->
          IO.puts("Chat completed in \#{measurements.duration}ns using \#{metadata.model}")
          IO.puts("Tokens used: \#{measurements.tokens}")
        end,
        nil
      )
  """

  @prefix [:elixir_llm]

  @doc """
  Executes a function within a telemetry span.
  """
  @spec span(atom(), map(), (-> result)) :: result when result: any()
  def span(event, metadata, fun) when is_atom(event) and is_function(fun, 0) do
    :telemetry.span(
      @prefix ++ [event],
      metadata,
      fn ->
        result = fun.()
        {result, metadata}
      end
    )
  end

  @doc """
  Emits a telemetry event.
  """
  @spec emit(atom(), map(), map()) :: :ok
  def emit(event, measurements \\ %{}, metadata \\ %{}) do
    :telemetry.execute(@prefix ++ [event], measurements, metadata)
  end

  @doc """
  Emits a tool call event.
  """
  @spec tool_call(String.t(), map()) :: :ok
  def tool_call(tool_name, arguments) do
    emit(:tool_call, %{}, %{tool_name: tool_name, arguments: arguments})
  end

  @doc """
  Emits a tool result event.
  """
  @spec tool_result(String.t(), term(), non_neg_integer()) :: :ok
  def tool_result(tool_name, result, duration) do
    emit(:tool_result, %{duration: duration}, %{tool_name: tool_name, result: result})
  end

  @doc """
  Emits a tool batch start event.
  """
  @spec tool_batch_start(non_neg_integer(), non_neg_integer(), boolean()) :: :ok
  def tool_batch_start(tool_count, max_concurrency, parallel) do
    emit(:tool_batch_start, %{system_time: System.system_time()}, %{
      tool_count: tool_count,
      max_concurrency: max_concurrency,
      parallel: parallel
    })
  end

  @doc """
  Emits a tool batch stop event.
  """
  @spec tool_batch_stop(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          :ok
  def tool_batch_stop(duration, success_count, error_count, timeout_count) do
    emit(:tool_batch_stop, %{duration: duration}, %{
      success_count: success_count,
      error_count: error_count,
      timeout_count: timeout_count
    })
  end
end
