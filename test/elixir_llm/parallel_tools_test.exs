defmodule ElixirLLM.ParallelToolsTest do
  use ExUnit.Case, async: true

  describe "parallel_tools/2" do
    test "defaults to true in new chat" do
      chat = ElixirLLM.new()
      assert chat.parallel_tools == true
    end

    test "can be disabled with false" do
      chat =
        ElixirLLM.new()
        |> ElixirLLM.parallel_tools(false)

      assert chat.parallel_tools == false
    end

    test "can set max concurrency with integer" do
      chat =
        ElixirLLM.new()
        |> ElixirLLM.parallel_tools(4)

      assert chat.parallel_tools == 4
    end

    test "can set full configuration with keyword list" do
      opts = [max_concurrency: 8, timeout: 60_000, ordered: false]

      chat =
        ElixirLLM.new()
        |> ElixirLLM.parallel_tools(opts)

      assert chat.parallel_tools == opts
    end
  end

  describe "tool_timeout/2" do
    test "defaults to 30_000 in new chat" do
      chat = ElixirLLM.new()
      assert chat.tool_timeout == 30_000
    end

    test "can be set to custom value" do
      chat =
        ElixirLLM.new()
        |> ElixirLLM.tool_timeout(120_000)

      assert chat.tool_timeout == 120_000
    end
  end

  describe "Chat struct fields" do
    test "parallel_tools field exists with correct default" do
      chat = %ElixirLLM.Chat{}
      assert Map.has_key?(chat, :parallel_tools)
      assert chat.parallel_tools == true
    end

    test "tool_timeout field exists with correct default" do
      chat = %ElixirLLM.Chat{}
      assert Map.has_key?(chat, :tool_timeout)
      assert chat.tool_timeout == 30_000
    end
  end

  describe "Telemetry module functions" do
    test "tool_batch_start/3 emits correct event" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-batch-start-#{inspect(ref)}",
        [:elixir_llm, :tool_batch_start],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:batch_start, measurements, metadata})
        end,
        nil
      )

      ElixirLLM.Telemetry.tool_batch_start(3, 4, true)

      assert_receive {:batch_start, %{system_time: _}, %{tool_count: 3, max_concurrency: 4, parallel: true}}

      :telemetry.detach("test-batch-start-#{inspect(ref)}")
    end

    test "tool_batch_stop/4 emits correct event" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-batch-stop-#{inspect(ref)}",
        [:elixir_llm, :tool_batch_stop],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:batch_stop, measurements, metadata})
        end,
        nil
      )

      ElixirLLM.Telemetry.tool_batch_stop(1000, 2, 1, 0)

      assert_receive {:batch_stop, %{duration: 1000}, %{success_count: 2, error_count: 1, timeout_count: 0}}

      :telemetry.detach("test-batch-stop-#{inspect(ref)}")
    end
  end

  describe "Application supervisor" do
    test "TaskSupervisor is running" do
      assert Process.whereis(ElixirLLM.TaskSupervisor) != nil
    end

    test "TaskSupervisor is a Task.Supervisor" do
      pid = Process.whereis(ElixirLLM.TaskSupervisor)
      info = Process.info(pid)
      # Check it's supervised by ElixirLLM.Supervisor
      assert is_pid(pid)
      assert Keyword.get(info, :status) == :waiting
    end
  end

  describe "builder function chaining" do
    test "parallel_tools can be chained with other options" do
      chat =
        ElixirLLM.new()
        |> ElixirLLM.model("gpt-4o")
        |> ElixirLLM.parallel_tools(4)
        |> ElixirLLM.tool_timeout(60_000)
        |> ElixirLLM.temperature(0.7)

      assert chat.model == "gpt-4o"
      assert chat.parallel_tools == 4
      assert chat.tool_timeout == 60_000
      assert chat.temperature == 0.7
    end

    test "parallel_tools false disables parallel execution" do
      chat =
        ElixirLLM.new()
        |> ElixirLLM.parallel_tools(false)

      assert chat.parallel_tools == false
    end

    test "parallel_tools with keyword list preserves all options" do
      chat =
        ElixirLLM.new()
        |> ElixirLLM.parallel_tools(max_concurrency: 2, timeout: 10_000, ordered: false)

      assert chat.parallel_tools == [max_concurrency: 2, timeout: 10_000, ordered: false]
    end
  end
end
