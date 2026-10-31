defmodule VerdictUIWeb.Components.LogsList do
  @moduledoc """
  Renders the engine log lines captured for a run (via
  `VerdictUI.LogCapture`), colorized by level. Hidden when there are no lines.
  """
  use VerdictUIWeb, :html

  attr :logs, :list, default: []

  def logs_list(assigns) do
    ~H"""
    <details :if={@logs != []} id="run-logs" class="mt-3">
      <summary class="cursor-pointer select-none text-sm text-zinc-500 hover:text-zinc-800 dark:text-zinc-400 dark:hover:text-zinc-200">
        Engine log ({length(@logs)})
      </summary>

      <div class="mt-2 space-y-0.5 overflow-x-auto rounded-md bg-zinc-100 p-3 font-mono text-xs dark:bg-zinc-900/60">
        <div :for={{level, msg} <- @logs} class={line_class(level)}>
          <span class="opacity-50">[{level}]</span> {msg}
        </div>
      </div>
    </details>
    """
  end

  defp line_class(:error), do: "text-red-700 dark:text-red-300"
  defp line_class(:warning), do: "text-yellow-700 dark:text-yellow-300"
  defp line_class(:info), do: "text-green-700 dark:text-green-300"
  defp line_class(_), do: "text-zinc-500 dark:text-zinc-400"
end
