defmodule VerdictUIWeb.Components.ResultsList do
  @moduledoc """
  Renders the per-rule results of a `Verdict.RunResult.to_map/1` run.

  Takes `results` — the `result["results"]` list, each a map with `name`,
  `result` (did it fire), and `conditions` (the per-leaf report). Renders one
   block per rule: a fired / not-fired badge, its event — the success event for
   fired rules, the declared failure event for rules that did not fire — plus
   the evaluated leaves (expected vs actual) and any short-circuited leaves.
  """
  use VerdictUIWeb, :html

  attr :results, :list, required: true

  def results_list(assigns) do
    ~H"""
    <div id="results" class="space-y-3">
      <div :for={r <- @results} class="rounded-lg border border-base-300 p-3">
        <div class="mb-2 flex items-center justify-between gap-2">
          <span class="font-semibold">{r["name"]}</span>

          <span class={if(r["result"], do: "badge badge-success", else: "badge badge-error")}>
            {if r["result"], do: "fired", else: "not fired"}
          </span>
        </div>

        <div
          :if={event = if r["result"], do: r["event"], else: r["failure_event"]}
          class="mb-2 flex flex-wrap items-center gap-x-2 text-sm"
        >
          <span class="opacity-60">{if r["result"], do: "event", else: "failure event"}</span>
          <span class={if r["result"], do: "font-mono text-primary", else: "font-mono text-error"}>
            {event["type"]}
          </span>
          <span :if={params = event["params"]} class="font-mono text-xs opacity-80">
            {Jason.encode!(params)}
          </span>
        </div>

        <ul :if={report = r["conditions"]} class="space-y-1 text-sm">
          <li
            :for={leaf <- report["changes"] ++ report["errors"]}
            class={[
              "flex flex-wrap items-center gap-x-2 rounded px-2 py-1",
              if(leaf["result"],
                do: "bg-green-500/10 text-green-300",
                else: "bg-red-500/10 text-red-300"
              )
            ]}
          >
            <span class="font-mono">{leaf["fact"]}</span>
            <span class="opacity-60">{leaf["operator"]}</span>
            <span class="font-mono">{fmt(leaf["value"])}</span>
            <span class="opacity-60">← actual</span>
            <span class="font-mono">{fmt(leaf["actual"])}</span>
          </li>
          <li
            :for={leaf <- report["empty_values"]}
            class="flex flex-wrap items-center gap-x-2 rounded bg-base-200/40 px-2 py-1 opacity-60"
          >
            <span class="font-mono">{leaf["fact"]}</span>
            <span>skipped (not reached)</span>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp fmt(nil), do: "∅"
  defp fmt(value) when is_binary(value), do: value
  defp fmt(value), do: Jason.encode!(value)
end
