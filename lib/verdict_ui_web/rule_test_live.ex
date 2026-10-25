defmodule VerdictUIWeb.RuleTestLive do
  @moduledoc false
  use VerdictUIWeb, :live_view

  alias VerdictUI
  alias VerdictUI.ConditionTree
  alias VerdictUIWeb.Components.{FactsEditor, ResultsList}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case VerdictUI.get_rule(id) do
      %VerdictUI.Rule{} = rule ->
        facts =
          rule.conditions
          |> ConditionTree.fact_names()
          |> Enum.map(&%{"name" => &1, "value" => ""})

        {:ok,
         assign(socket,
           rule: rule,
           facts: facts,
           result: nil,
           error: nil,
           allow_unsafe: false,
           allow_undefined_facts: false,
           allow_undefined_conditions: false,
           strict: false,
           replace_facts_in_event_params: false,
           report: "full",
           schedule: "serial",
           parallel_concurrency: nil,
           log_level: nil
         )}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/rules")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Test: {@rule.name}
        <:actions>
          <.link patch={~p"/rules/#{@rule.id}/edit"} class="btn btn-ghost btn-sm">Edit</.link>
        </:actions>
      </.header>

      <div class="grid gap-6 lg:grid-cols-2">
        <div class="rounded-lg border border-zinc-800 p-4">
          <div class="mb-3 flex items-center justify-between">
            <h2 class="font-semibold text-zinc-200">Runtime facts</h2>
            <button type="button" phx-click="add-fact" class="btn btn-ghost btn-sm">+ fact</button>
          </div>

          <form id="test-form" phx-submit="run" phx-change="fact" class="space-y-2">
            <FactsEditor.facts_editor rows={@facts} />

            <p :if={@facts == []} class="text-sm text-zinc-500">
              No facts referenced. Add one to supply a runtime value.
            </p>

            <label class="flex items-center gap-2 text-sm text-zinc-400">
              <input
                type="checkbox"
                name="allow_unsafe"
                phx-change="allow-unsafe"
                class="checkbox checkbox-sm"
              /> Allow unsafe EEx templates
            </label>

            <label class="flex items-center gap-2 text-sm text-zinc-400">
              <input
                type="checkbox"
                name="allow_undefined_facts"
                phx-change="allow-undefined-facts"
                class="checkbox checkbox-sm"
              /> Allow undefined facts
            </label>

            <label class="flex items-center gap-2 text-sm text-zinc-400">
              <input
                type="checkbox"
                name="allow_undefined_conditions"
                phx-change="allow-undefined-conditions"
                checked={@allow_undefined_conditions}
                class="checkbox checkbox-sm"
              /> Allow undefined conditions
            </label>

            <label class="flex items-center gap-2 text-sm text-zinc-400">
              <input
                type="checkbox"
                name="strict"
                phx-change="strict"
                checked={@strict}
                class="checkbox checkbox-sm"
              /> Strict (evaluate all conditions)
            </label>

            <label class="flex items-center gap-2 text-sm text-zinc-400">
              <input
                type="checkbox"
                name="replace_facts_in_event_params"
                phx-change="replace-facts-in-event-params"
                checked={@replace_facts_in_event_params}
                class="checkbox checkbox-sm"
              /> Replace facts in event params
            </label>

            <div class="grid grid-cols-2 gap-2 pt-1 text-sm text-zinc-400">
              <label class="flex flex-col gap-1">
                Report
                <select name="report" phx-change="report" class="select select-xs">
                  <option value="full" selected={@report == "full"}>Full</option>
                  <option value="failures_only" selected={@report == "failures_only"}>
                    Failures
                  </option>
                  <option value="result_only" selected={@report == "result_only"}>Result</option>
                </select>
              </label>

              <label class="flex flex-col gap-1">
                Schedule
                <select name="schedule" phx-change="schedule" class="select select-xs">
                  <option value="serial" selected={@schedule == "serial"}>Serial</option>
                  <option value="parallel" selected={@schedule == "parallel"}>Parallel</option>
                </select>
              </label>

              <label class="flex flex-col gap-1">
                Concurrency
                <input
                  name="parallel_concurrency"
                  type="number"
                  min="1"
                  value={@parallel_concurrency || ""}
                  placeholder="auto"
                  phx-change="parallel-concurrency"
                  class="input input-xs"
                />
              </label>

              <label class="flex flex-col gap-1">
                Log
                <select name="log_level" phx-change="log-level" class="select select-xs">
                  <option value="" selected={@log_level in [nil, ""]}>Off</option>
                  <option value="debug" selected={@log_level == "debug"}>debug</option>
                  <option value="info" selected={@log_level == "info"}>info</option>
                  <option value="warning" selected={@log_level == "warning"}>warning</option>
                  <option value="error" selected={@log_level == "error"}>error</option>
                </select>
              </label>
            </div>

            <div class="pt-2">
              <button type="submit" id="run-btn" class="btn btn-primary btn-sm">Run</button>
            </div>
          </form>
        </div>

        <div class="rounded-lg border border-zinc-800 p-4">
          <h2 class="mb-3 font-semibold text-zinc-200">Result</h2>

          <div :if={@error} id="run-error" class="alert alert-error">
            <p class="text-sm">{@error}</p>
          </div>

          <div :if={@result} id="run-result">
            <ResultsList.results_list results={@result["results"]} />
          </div>

          <div :if={!@result && !@error} class="text-sm text-zinc-500">
            Fill in the facts and press Run to evaluate this rule.
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("add-fact", _params, socket) do
    {:noreply, assign(socket, facts: socket.assigns.facts ++ [%{"name" => "", "value" => ""}])}
  end

  @impl true
  def handle_event("remove-fact", %{"value" => idx}, socket) do
    i = String.to_integer(idx)

    {:noreply,
     assign(socket, facts: List.delete_at(socket.assigns.facts, i), result: nil, error: nil)}
  end

  @impl true
  def handle_event("fact", params, socket) do
    target =
      case params["_target"] do
        [t] when is_binary(t) -> t
        _ -> params |> Map.delete("_target") |> Map.keys() |> hd()
      end

    value = Map.get(params, target)

    case String.split(target, "-") do
      ["fact", idx, field] ->
        i = String.to_integer(idx)
        row = Enum.at(socket.assigns.facts, i)

        {:noreply,
         assign(socket,
           facts: List.replace_at(socket.assigns.facts, i, Map.put(row, field, value))
         )}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("allow-unsafe", params, socket) do
    checked = Map.has_key?(params, "allow_unsafe")
    {:noreply, assign(socket, allow_unsafe: checked, result: nil, error: nil)}
  end

  @impl true
  def handle_event("allow-undefined-facts", params, socket) do
    checked = Map.has_key?(params, "allow_undefined_facts")
    {:noreply, assign(socket, allow_undefined_facts: checked, result: nil, error: nil)}
  end

  @impl true
  def handle_event("allow-undefined-conditions", params, socket) do
    checked = Map.has_key?(params, "allow_undefined_conditions")
    {:noreply, assign(socket, allow_undefined_conditions: checked, result: nil, error: nil)}
  end

  @impl true
  def handle_event("strict", params, socket) do
    checked = Map.has_key?(params, "strict")
    {:noreply, assign(socket, strict: checked, result: nil, error: nil)}
  end

  @impl true
  def handle_event("replace-facts-in-event-params", params, socket) do
    checked = Map.has_key?(params, "replace_facts_in_event_params")
    {:noreply, assign(socket, replace_facts_in_event_params: checked, result: nil, error: nil)}
  end

  @impl true
  def handle_event("report", %{"report" => report}, socket) do
    {:noreply, assign(socket, report: report, result: nil, error: nil)}
  end

  @impl true
  def handle_event("schedule", %{"schedule" => schedule}, socket) do
    {:noreply, assign(socket, schedule: schedule, result: nil, error: nil)}
  end

  @impl true
  def handle_event("parallel-concurrency", %{"parallel_concurrency" => raw}, socket) do
    concurrency =
      case Integer.parse(raw || "") do
        {n, _} -> n
        :error -> nil
      end

    {:noreply, assign(socket, parallel_concurrency: concurrency, result: nil, error: nil)}
  end

  @impl true
  def handle_event("log-level", %{"log_level" => level}, socket) do
    log_level = if level in [nil, ""], do: nil, else: level
    {:noreply, assign(socket, log_level: log_level, result: nil, error: nil)}
  end

  @impl true
  def handle_event("run", _params, socket) do
    facts =
      socket.assigns.facts
      |> Enum.reject(&(&1["name"] in [nil, ""]))
      |> Map.new(&{&1["name"], ConditionTree.parse_value(&1["value"])})

    opts = VerdictUI.run_opts(assign_opts(socket))

    case VerdictUI.run_rules([socket.assigns.rule], facts, opts) do
      {:ok, result} -> {:noreply, assign(socket, result: result, error: nil)}
      {:error, msg} -> {:noreply, assign(socket, result: nil, error: msg)}
    end
  end

  defp assign_opts(socket) do
    %{
      allow_unsafe: socket.assigns.allow_unsafe,
      allow_undefined_facts: socket.assigns.allow_undefined_facts,
      allow_undefined_conditions: socket.assigns.allow_undefined_conditions,
      strict: socket.assigns.strict,
      replace_facts_in_event_params: socket.assigns.replace_facts_in_event_params,
      report: socket.assigns.report,
      schedule: socket.assigns.schedule,
      parallel_concurrency: socket.assigns.parallel_concurrency,
      log_level: socket.assigns.log_level
    }
  end
end
