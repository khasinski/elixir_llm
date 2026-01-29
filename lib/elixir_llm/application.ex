defmodule ElixirLLM.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: ElixirLLM.TaskSupervisor}
    ]

    opts = [strategy: :one_for_one, name: ElixirLLM.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
