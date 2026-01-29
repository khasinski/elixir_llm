defmodule ElixirLLM.MCP do
  @moduledoc """
  Model Context Protocol (MCP) client for connecting to MCP servers.

  MCP allows LLMs to interact with external tools and data sources through
  a standardized protocol.

  ## Examples

      # Connect to an MCP server
      {:ok, conn} = ElixirLLM.MCP.connect("npx", ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"])

      # List available tools
      {:ok, tools} = ElixirLLM.MCP.list_tools(conn)

      # Use MCP tools with chat
      {:ok, response, chat} =
        ElixirLLM.new()
        |> ElixirLLM.model("claude-sonnet-4-20250514")
        |> ElixirLLM.mcp_server(conn)
        |> ElixirLLM.ask("Read the contents of /tmp/test.txt")

      # Call a tool directly
      {:ok, result} = ElixirLLM.MCP.call_tool(conn, "read_file", %{path: "/tmp/test.txt"})

      # List resources
      {:ok, resources} = ElixirLLM.MCP.list_resources(conn)

      # Read a resource
      {:ok, content} = ElixirLLM.MCP.read_resource(conn, "file:///tmp/test.txt")

      # Disconnect when done
      :ok = ElixirLLM.MCP.disconnect(conn)

  ## MCP Protocol

  This implementation supports the MCP JSON-RPC protocol over stdio.
  See https://modelcontextprotocol.io for more information.
  """

  use GenServer

  require Logger

  @type t :: %__MODULE__{
          pid: pid(),
          name: String.t(),
          tools: [map()],
          resources: [map()],
          prompts: [map()]
        }

  defstruct [:pid, :name, :tools, :resources, :prompts]

  @doc """
  Connects to an MCP server via stdio.

  ## Options

    * `:name` - Name for the connection (default: command name)
    * `:timeout` - Connection timeout in ms (default: 30000)

  ## Examples

      # Filesystem server
      {:ok, conn} = ElixirLLM.MCP.connect("npx", ["-y", "@modelcontextprotocol/server-filesystem", "/path"])

      # Custom server
      {:ok, conn} = ElixirLLM.MCP.connect("python", ["my_mcp_server.py"], name: "custom")
  """
  @spec connect(String.t(), [String.t()], keyword()) :: {:ok, t()} | {:error, term()}
  def connect(command, args \\ [], opts \\ []) do
    name = Keyword.get(opts, :name, command)
    timeout = Keyword.get(opts, :timeout, 30_000)

    case GenServer.start_link(__MODULE__, {command, args, name, timeout}, []) do
      {:ok, pid} ->
        # Initialize and get capabilities
        with :ok <- initialize(pid, timeout),
             {:ok, tools} <- list_tools_internal(pid, timeout),
             {:ok, resources} <- list_resources_internal(pid, timeout) do
          {:ok,
           %__MODULE__{
             pid: pid,
             name: name,
             tools: tools,
             resources: resources,
             prompts: []
           }}
        else
          {:error, reason} ->
            GenServer.stop(pid)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Disconnects from the MCP server.
  """
  @spec disconnect(t()) :: :ok
  def disconnect(%__MODULE__{pid: pid}) do
    GenServer.stop(pid)
  end

  @doc """
  Lists tools available from the MCP server.

  **Note:** Returns cached data from when the connection was established.
  Use `refresh_tools/1` to fetch the latest tools from the server.
  """
  @spec list_tools(t()) :: {:ok, [map()]} | {:error, term()}
  def list_tools(%__MODULE__{tools: tools}), do: {:ok, tools}

  @doc """
  Refreshes the tools list from the MCP server.
  """
  @spec refresh_tools(t()) :: {:ok, t()} | {:error, term()}
  def refresh_tools(%__MODULE__{pid: pid} = conn) do
    case list_tools_internal(pid, 30_000) do
      {:ok, tools} -> {:ok, %{conn | tools: tools}}
      error -> error
    end
  end

  @doc """
  Calls a tool on the MCP server.

  ## Examples

      {:ok, result} = ElixirLLM.MCP.call_tool(conn, "read_file", %{path: "/tmp/test.txt"})
  """
  @spec call_tool(t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def call_tool(%__MODULE__{pid: pid}, name, args) do
    GenServer.call(pid, {:call_tool, name, args}, 60_000)
  end

  @doc """
  Lists resources available from the MCP server.

  **Note:** Returns cached data from when the connection was established.
  """
  @spec list_resources(t()) :: {:ok, [map()]} | {:error, term()}
  def list_resources(%__MODULE__{resources: resources}), do: {:ok, resources}

  @doc """
  Reads a resource from the MCP server.

  ## Examples

      {:ok, content} = ElixirLLM.MCP.read_resource(conn, "file:///tmp/test.txt")
  """
  @spec read_resource(t(), String.t()) :: {:ok, term()} | {:error, term()}
  def read_resource(%__MODULE__{pid: pid}, uri) do
    GenServer.call(pid, {:read_resource, uri}, 30_000)
  end

  @doc """
  Lists prompts available from the MCP server.
  """
  @spec list_prompts(t()) :: {:ok, [map()]} | {:error, term()}
  def list_prompts(%__MODULE__{prompts: prompts}), do: {:ok, prompts}

  @doc """
  Gets a prompt from the MCP server.
  """
  @spec get_prompt(t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def get_prompt(%__MODULE__{pid: pid}, name, args \\ %{}) do
    GenServer.call(pid, {:get_prompt, name, args}, 30_000)
  end

  # ===========================================================================
  # GenServer Implementation
  # ===========================================================================

  @impl true
  def init({command, args, name, _timeout}) do
    executable = System.find_executable(command)

    if executable do
      port =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :exit_status,
          {:args, args},
          {:line, 1024 * 1024}
        ])

      {:ok,
       %{
         port: port,
         name: name,
         buffer: "",
         pending: %{},
         request_id: 0
       }}
    else
      {:stop, {:executable_not_found, command}}
    end
  end

  @impl true
  def handle_call({:request, method, params}, from, state) do
    {id, state} = next_request_id(state)

    request = %{
      jsonrpc: "2.0",
      id: id,
      method: method,
      params: params || %{}
    }

    send_request(state.port, request)
    state = put_in(state.pending[id], from)
    {:noreply, state}
  end

  def handle_call({:call_tool, name, args}, from, state) do
    {id, state} = next_request_id(state)

    request = %{
      jsonrpc: "2.0",
      id: id,
      method: "tools/call",
      params: %{name: name, arguments: args}
    }

    send_request(state.port, request)
    state = put_in(state.pending[id], from)
    {:noreply, state}
  end

  def handle_call({:read_resource, uri}, from, state) do
    {id, state} = next_request_id(state)

    request = %{
      jsonrpc: "2.0",
      id: id,
      method: "resources/read",
      params: %{uri: uri}
    }

    send_request(state.port, request)
    state = put_in(state.pending[id], from)
    {:noreply, state}
  end

  def handle_call({:get_prompt, name, args}, from, state) do
    {id, state} = next_request_id(state)

    request = %{
      jsonrpc: "2.0",
      id: id,
      method: "prompts/get",
      params: %{name: name, arguments: args}
    }

    send_request(state.port, request)
    state = put_in(state.pending[id], from)
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    state = process_line(line, state)
    {:noreply, state}
  end

  def handle_info({port, {:data, {:noeol, data}}}, %{port: port} = state) do
    # Accumulate partial line
    {:noreply, %{state | buffer: state.buffer <> data}}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    # Server exited, reply to all pending requests with error
    for {_id, from} <- state.pending do
      GenServer.reply(from, {:error, {:server_exited, status}})
    end

    {:stop, {:server_exited, status}, state}
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp initialize(pid, timeout) do
    request = {:request, "initialize", %{
      protocolVersion: "2024-11-05",
      capabilities: %{},
      clientInfo: %{
        name: "elixir_llm",
        version: "0.4.0"
      }
    }}

    case GenServer.call(pid, request, timeout) do
      {:ok, _result} ->
        # Send initialized notification
        GenServer.cast(pid, {:notify, "notifications/initialized", %{}})
        :ok

      {:error, _} = error ->
        error
    end
  end

  defp list_tools_internal(pid, timeout) do
    case GenServer.call(pid, {:request, "tools/list", %{}}, timeout) do
      {:ok, %{"tools" => tools}} -> {:ok, tools}
      {:ok, _} -> {:ok, []}
      error -> error
    end
  end

  defp list_resources_internal(pid, timeout) do
    case GenServer.call(pid, {:request, "resources/list", %{}}, timeout) do
      {:ok, %{"resources" => resources}} -> {:ok, resources}
      {:ok, _} -> {:ok, []}
      error -> error
    end
  end

  defp next_request_id(state) do
    id = state.request_id + 1
    {id, %{state | request_id: id}}
  end

  defp send_request(port, request) do
    json = Jason.encode!(request)
    Port.command(port, json <> "\n")
  end

  defp process_line(line, state) do
    # Combine with any buffered data
    full_line = state.buffer <> line
    state = %{state | buffer: ""}

    case Jason.decode(full_line) do
      {:ok, response} ->
        handle_response(response, state)

      {:error, _} ->
        # Not valid JSON, might be log output - ignore
        Logger.debug("MCP: Non-JSON output: #{full_line}")
        state
    end
  end

  defp handle_response(%{"id" => id, "result" => result}, state) do
    case Map.pop(state.pending, id) do
      {nil, state} ->
        # No pending request with this ID
        state

      {from, pending} ->
        GenServer.reply(from, {:ok, result})
        %{state | pending: pending}
    end
  end

  defp handle_response(%{"id" => id, "error" => error}, state) do
    case Map.pop(state.pending, id) do
      {nil, state} ->
        state

      {from, pending} ->
        GenServer.reply(from, {:error, error})
        %{state | pending: pending}
    end
  end

  defp handle_response(%{"method" => method, "params" => params}, state) do
    # Notification from server
    Logger.debug("MCP notification: #{method} - #{inspect(params)}")
    state
  end

  defp handle_response(_response, state) do
    state
  end

  @impl true
  def handle_cast({:notify, method, params}, state) do
    notification = %{
      jsonrpc: "2.0",
      method: method,
      params: params
    }

    send_request(state.port, notification)
    {:noreply, state}
  end
end
