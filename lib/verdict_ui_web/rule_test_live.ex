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
           allow_unsafe: false
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
  def handle_event("run", _params, socket) do
    facts =
      socket.assigns.facts
      |> Enum.reject(&(&1["name"] in [nil, ""]))
      |> Map.new(&{&1["name"], ConditionTree.parse_value(&1["value"])})

    opts = if socket.assigns.allow_unsafe, do: [allow_unsafe_eex: true], else: []

    case VerdictUI.run_rules([socket.assigns.rule], facts, opts) do
      {:ok, result} -> {:noreply, assign(socket, result: result, error: nil)}
      {:error, msg} -> {:noreply, assign(socket, result: nil, error: msg)}
    end
  end
end
