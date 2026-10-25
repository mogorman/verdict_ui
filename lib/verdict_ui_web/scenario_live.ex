defmodule VerdictUIWeb.ScenarioLive do
  @moduledoc false
  use VerdictUIWeb, :live_view

  alias VerdictUI
  alias VerdictUI.ConditionTree
  alias VerdictUIWeb.Components.{FactsEditor, ResultsList}

  @impl true
  def mount(params, _session, socket) do
    rules = VerdictUI.list_rules()

    case params["id"] do
      nil ->
        {:ok,
         assign(socket,
           mode: :new,
           scenario: %VerdictUI.Scenario{},
           rules: rules,
           name: "",
           selected_ids: [],
           facts: [],
           result: nil,
           error: nil,
           changeset: nil,
           allow_unsafe: false,
           allow_undefined_facts: false
         )}

      id ->
        case VerdictUI.get_scenario(id) do
          %VerdictUI.Scenario{} = scenario ->
            {:ok,
             assign(socket,
               mode: :edit,
               scenario: scenario,
               rules: rules,
               name: scenario.name,
               selected_ids: scenario.rule_ids,
               facts: facts_to_rows(scenario.facts),
               result: nil,
               error: nil,
               changeset: nil,
               allow_unsafe: scenario.allow_unsafe || false,
               allow_undefined_facts: scenario.allow_undefined_facts || false
             )}

          _ ->
            {:ok, push_navigate(socket, to: ~p"/scenarios")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {if @mode == :new, do: "New scenario", else: "Scenario: #{@scenario.name}"}
        <:actions>
          <.link patch={~p"/scenarios"} class="btn btn-ghost btn-sm">Cancel</.link>
        </:actions>
      </.header>

      <div :if={@changeset} id="save-errors" class="alert alert-error mb-4">
        <p :for={{field, {msg, _opts}} <- @changeset.errors} class="text-sm">
          <span class="font-semibold">{field}:</span> {msg}
        </p>
      </div>

      <div class="grid gap-6 lg:grid-cols-2">
        <div class="space-y-5 rounded-lg border border-zinc-800 p-4">
          <div class="flex gap-2">
            <button type="button" id="save-btn" phx-click="save" class="btn btn-primary btn-sm">
              Save
            </button>
            <button type="button" id="run-btn" phx-click="run" class="btn btn-sm">Run</button>
          </div>

          <form id="scenario-form" class="space-y-5">
            <div>
              <label class="label mb-1" for="scenario-name">Name</label>

              <input
                id="scenario-name"
                name="scenario[name]"
                type="text"
                value={@name}
                placeholder="e.g. game-over"
                phx-change="name"
                class="w-full input"
              />
            </div>

            <div>
              <p class="label mb-2">Rules to run ({length(@selected_ids)} selected)</p>

              <div class="max-h-64 space-y-1 overflow-y-auto rounded-md border border-zinc-800 p-2">
                <label
                  :for={rule <- @rules}
                  class="flex cursor-pointer items-center gap-2 rounded px-2 py-1 hover:bg-zinc-900/50"
                >
                  <input
                    type="checkbox"
                    name={"rule-#{rule.id}"}
                    value={rule.id}
                    checked={rule.id in @selected_ids}
                    phx-change="toggle-rule"
                  />
                  <span class="text-sm">{rule.name}</span>
                  <span class="ml-auto text-xs text-zinc-500">p{rule.priority}</span>
                </label>
              </div>

              <p :if={@rules == []} class="mt-2 text-sm text-zinc-500">
                No rules yet. <.link patch={~p"/rules/new"} class="link">Create one</.link>
              </p>
            </div>
          </form>

          <div>
            <div class="mb-2 flex items-center justify-between">
              <p class="label mb-0">Runtime facts</p>
              <button type="button" phx-click="add-fact" class="btn btn-ghost btn-sm">+ fact</button>
            </div>

            <form id="scenario-facts" phx-change="fact" class="space-y-2">
              <FactsEditor.facts_editor rows={@facts} />
              <p :if={@facts == []} class="text-sm text-zinc-500">
                Add the facts your rules reference.
              </p>
            </form>
          </div>

          <form id="scenario-options" class="space-y-2">
            <label
              id="allow-unsafe"
              for="scenario-allow-unsafe"
              class="flex cursor-pointer items-start gap-2 rounded-md border border-zinc-800 bg-zinc-900/40 px-3 py-2 text-sm hover:bg-zinc-900/70"
            >
              <input
                id="scenario-allow-unsafe"
                type="checkbox"
                name="allow_unsafe"
                phx-change="allow-unsafe"
                checked={@allow_unsafe}
                class="checkbox mt-0.5 shrink-0"
              />
              <span>
                <span class="font-medium text-zinc-200">Allow unsafe EEx templates</span>
                <span class="block text-xs text-zinc-500">
                  Enables control-flow templates (if / for / cond) in event params.
                </span>
              </span>
            </label>

            <label
              id="allow-undefined-facts"
              for="scenario-allow-undefined-facts"
              class="flex cursor-pointer items-start gap-2 rounded-md border border-zinc-800 bg-zinc-900/40 px-3 py-2 text-sm hover:bg-zinc-900/70"
            >
              <input
                id="scenario-allow-undefined-facts"
                type="checkbox"
                name="allow_undefined_facts"
                phx-change="allow-undefined-facts"
                checked={@allow_undefined_facts}
                class="checkbox mt-0.5 shrink-0"
              />
              <span>
                <span class="font-medium text-zinc-200">Allow undefined facts</span>
                <span class="block text-xs text-zinc-500">
                  Facts referenced by a rule but not provided evaluate as nil instead of
                  erroring.
                </span>
              </span>
            </label>
          </form>
        </div>

        <div class="rounded-lg border border-zinc-800 p-4">
          <h2 class="mb-3 font-semibold text-zinc-200">Result</h2>

          <div :if={@error} id="run-error" class="alert alert-error">
            <p class="text-sm">{@error}</p>
          </div>

          <div :if={@result} id="run-result">
            <ResultsList.results_list results={@result["results"]} />

            <details class="mt-3">
              <summary class="cursor-pointer select-none text-sm text-zinc-400 hover:text-zinc-200">
                Raw JSON
              </summary>

              <pre
                id="run-raw-json"
                class="mt-2 overflow-x-auto rounded-md bg-zinc-900/60 p-3 text-xs font-mono text-zinc-300"
              >
                {Jason.encode!(@result, pretty: true)}
              </pre>
            </details>
          </div>

          <div :if={!@result && !@error} class="text-sm text-zinc-500">
            Select rules, add facts, and press Run to evaluate them together.
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("name", params, socket) do
    name = (params["scenario"] || %{})["name"]
    {:noreply, assign(socket, name: name, changeset: nil)}
  end

  @impl true
  def handle_event("toggle-rule", params, socket) do
    target = List.first(params["_target"])
    id = String.replace_prefix(target, "rule-", "")
    checked? = Map.has_key?(params, target)

    selected_ids =
      if checked? do
        if id in socket.assigns.selected_ids do
          socket.assigns.selected_ids
        else
          socket.assigns.selected_ids ++ [id]
        end
      else
        List.delete(socket.assigns.selected_ids, id)
      end

    {:noreply, assign(socket, selected_ids: selected_ids, result: nil)}
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
  def handle_event("save", _params, socket) do
    attrs = %{
      name: socket.assigns.name,
      facts: facts_map(socket.assigns.facts),
      rule_ids: socket.assigns.selected_ids,
      allow_unsafe: socket.assigns.allow_unsafe,
      allow_undefined_facts: socket.assigns.allow_undefined_facts
    }

    result =
      case socket.assigns.mode do
        :new -> VerdictUI.create_scenario(attrs)
        :edit -> VerdictUI.update_scenario(socket.assigns.scenario, attrs)
      end

    case result do
      {:ok, scenario} ->
        {:noreply,
         socket
         |> put_flash(:info, "Scenario saved.")
         |> push_navigate(to: ~p"/scenarios/#{scenario.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_event("allow-unsafe", params, socket) do
    checked = Map.has_key?(params, "allow_unsafe")
    {:noreply, assign(socket, allow_unsafe: checked, result: nil)}
  end

  @impl true
  def handle_event("allow-undefined-facts", params, socket) do
    checked = Map.has_key?(params, "allow_undefined_facts")
    {:noreply, assign(socket, allow_undefined_facts: checked, result: nil)}
  end

  @impl true
  def handle_event("run", _params, socket) do
    rules =
      socket.assigns.rules
      |> Enum.filter(&(&1.id in MapSet.new(socket.assigns.selected_ids)))

    opts = VerdictUI.run_opts(socket.assigns.allow_unsafe, socket.assigns.allow_undefined_facts)

    case VerdictUI.run_rules(rules, facts_map(socket.assigns.facts), opts) do
      {:ok, result} -> {:noreply, assign(socket, result: result, error: nil)}
      {:error, msg} -> {:noreply, assign(socket, result: nil, error: msg)}
    end
  end

  defp facts_to_rows(facts) do
    Enum.map(facts, fn {name, value} ->
      %{"name" => to_string(name), "value" => ConditionTree.value_to_input(value)}
    end)
  end

  defp facts_map(facts) do
    facts
    |> Enum.reject(&(&1["name"] in [nil, ""]))
    |> Enum.map(&{&1["name"], ConditionTree.parse_value(&1["value"])})
    |> Map.new()
  end
end
