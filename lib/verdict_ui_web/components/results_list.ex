defmodule VerdictUIWeb.Components.ResultsList do
  @moduledoc """
  Renders the per-rule results of a `Verdict.RunResult.to_map/1` run.

  Takes `results` — the `result["results"]` list, each a map with `name`,
  `result` (did it fire), and `conditions` (the flat per-leaf report). When
  `rules_by_name` (a `rule name => rule` map) is supplied, each rule's result is
  shown as its **nested condition tree** — `ALL` / `ANY` / `NOT` blocks with a
  pass / fail badge per node — by walking the rule's stored condition tree and
  joining each leaf to the flat report. Without it (or when a rule is missing)
  the flat leaf list is shown instead.
  """
  use VerdictUIWeb, :html

  attr :results, :list, required: true
  attr :rules_by_name, :map, default: %{}

  def results_list(assigns) do
    pairs =
      Enum.map(assigns.results, fn r ->
        {r, annotated_tree(Map.get(assigns.rules_by_name, r["name"]), r["conditions"]),
         r["conditions"]}
      end)

    assigns = assign(assigns, pairs: pairs)

    ~H"""
    <div id="results" class="space-y-3">
      <div :for={{r, tree, report} <- @pairs} class="rounded-lg border border-base-300 p-3">
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

        <.condition_block :if={tree} node={tree} />

        <ul :if={!tree and report} class="space-y-1 text-sm">
          <li
            :for={leaf <- (report["changes"] || []) ++ (report["errors"] || [])}
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
            :for={leaf <- report["empty_values"] || []}
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

  # --- nested condition tree ---------------------------------------------------

  attr :node, :map, required: true

  def condition_block(assigns) do
    ~H"""
    <div
      :if={@node.kind == :leaf}
      class={[
        "flex flex-wrap items-center gap-x-2 rounded px-2 py-1 text-sm",
        if(@node.badge == :pass,
          do: "bg-green-500/10 text-green-300",
          else:
            if(@node.badge == :fail,
              do: "bg-red-500/10 text-red-300",
              else: "bg-base-200/40 text-zinc-400"
            )
        )
      ]}
    >
      <span class="font-mono">{@node.summary}</span>
      <span class="text-xs opacity-70">{@node.detail}</span>
    </div>

    <div :if={@node.kind == :group} class="rounded-md border border-zinc-700/60 p-2">
      <div class="mb-1 flex items-center gap-2">
        <span class="rounded bg-zinc-800 px-1.5 py-0.5 text-xs font-semibold tracking-wide text-zinc-300">{@node.label}</span>
        <span class={badge_class(@node.badge)}>{badge_label(@node.badge)}</span>
      </div>

      <div class="ml-1 space-y-1 border-l border-zinc-700/50 pl-3">
        <.condition_block :for={child <- @node.children} node={child} />
      </div>
    </div>

    <div :if={@node.kind == :not} class="rounded-md border border-zinc-700/60 p-2">
      <div class="mb-1 flex items-center gap-2">
        <span class="rounded bg-zinc-800 px-1.5 py-0.5 text-xs font-semibold tracking-wide text-zinc-300">NOT</span>
        <span class={badge_class(@node.badge)}>{badge_label(@node.badge)}</span>
      </div>

      <div class="ml-1 border-l border-zinc-700/50 pl-3">
        <.condition_block node={@node.child} />
      </div>
    </div>

    <div
      :if={@node.kind == :ref}
      class="flex items-center gap-2 rounded bg-base-200/40 px-2 py-1 text-sm text-zinc-400"
    >
      <span>condition:</span>
      <span class="font-mono">{@node.name}</span>
    </div>
    """
  end

  # Walks the rule's stored condition tree, joining each leaf to the flat report,
  # and tags every node with a pass / fail / unknown badge. Returns `nil` when the
  # rule (or its conditions) is unavailable, so the caller falls back to the flat list.
  defp annotated_tree(nil, _report), do: nil
  defp annotated_tree(%{conditions: nil}, _report), do: nil

  defp annotated_tree(%{conditions: conds}, report),
    do: annotate(conditions_map(conds), build_index(report))

  defp conditions_map(%Verdict.Condition{} = c), do: Verdict.Types.Condition.to_map(c)
  defp conditions_map(map) when is_map(map), do: map

  # A `{fact, operator, path_or_nil} => leaf report` map. Evaluated leaves
  # (changes/errors) are keyed with a `nil` path (the flat report drops the path
  # there); short-circuited leaves (empty_values) keep theirs.
  # ponytail: keyed by fact+operator(+path); two identical leaves in one rule would
  # collide and the second shows the first's result. Upgrade to a per-leaf id if that bites.
  defp build_index(nil), do: %{}

  defp build_index(report) do
    changes =
      for c <- report["changes"] || [],
          do: {{c["fact"], c["operator"], nil}, %{result: true, actual: c["actual"]}}

    errors =
      for e <- report["errors"] || [],
          do: {{e["fact"], e["operator"], nil}, %{result: false, actual: e["actual"]}}

    skipped =
      for s <- report["empty_values"] || [],
          do: {{s["fact"], s["operator"], s["path"]}, %{skipped: true}}

    Map.new(changes ++ errors ++ skipped)
  end

  defp annotate(%{"fact" => fact} = node, index) do
    op = node["operator"]
    {badge, detail} = leaf_result(index, fact, op, node["path"])
    %{kind: :leaf, badge: badge, summary: "#{fact} #{op} #{fmt(node["value"])}", detail: detail}
  end

  defp annotate(%{"all" => children}, index) do
    cs = Enum.map(children, &annotate(&1, index))
    %{kind: :group, label: "ALL", badge: combine(:all, cs), children: cs}
  end

  defp annotate(%{"any" => children}, index) do
    cs = Enum.map(children, &annotate(&1, index))
    %{kind: :group, label: "ANY", badge: combine(:any, cs), children: cs}
  end

  defp annotate(%{"not" => child}, index) do
    c = annotate(child, index)
    %{kind: :not, badge: negate(c.badge), child: c}
  end

  defp annotate(%{"condition" => name}, _index), do: %{kind: :ref, name: name}

  # A pathed evaluated leaf lands under a `nil` path key, so fall back to that.
  defp leaf_result(index, fact, op, path) do
    entry = Map.get(index, {fact, op, path}) || Map.get(index, {fact, op, nil})

    case entry do
      %{result: true, actual: a} -> {:pass, "actual: " <> fmt(a)}
      %{result: false, actual: a} -> {:fail, "actual: " <> fmt(a)}
      %{skipped: true} -> {:skip, "not evaluated"}
      nil -> {:skip, "not in report"}
    end
  end

  defp combine(:all, children) do
    badges = Enum.map(children, & &1.badge)

    cond do
      :fail in badges -> :fail
      Enum.all?(badges, &(&1 == :pass)) -> :pass
      true -> :unknown
    end
  end

  defp combine(:any, children) do
    badges = Enum.map(children, & &1.badge)

    cond do
      :pass in badges -> :pass
      Enum.all?(badges, &(&1 == :fail)) -> :fail
      true -> :unknown
    end
  end

  defp negate(:pass), do: :fail
  defp negate(:fail), do: :pass
  defp negate(_), do: :unknown

  defp badge_class(:pass), do: "text-green-300"
  defp badge_class(:fail), do: "text-red-300"
  defp badge_class(_), do: "text-zinc-500"

  defp badge_label(:pass), do: "✓"
  defp badge_label(:fail), do: "✗"
  defp badge_label(_), do: "—"

  defp fmt(nil), do: "∅"
  defp fmt(value) when is_binary(value), do: value
  defp fmt(value), do: Jason.encode!(value)
end
