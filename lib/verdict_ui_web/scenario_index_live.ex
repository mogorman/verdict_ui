defmodule VerdictUIWeb.ScenarioIndexLive do
  @moduledoc false
  use VerdictUIWeb, :live_view

  alias VerdictUI

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream_scenarios(socket), temporary_assigns: [scenarios: []]}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Scenarios
        <:actions>
          <.link patch={~p"/scenarios/new"} class="btn btn-primary btn-sm">New scenario</.link>
        </:actions>
      </.header>

      <div
        id="scenarios"
        phx-update="stream"
        class="rounded-lg border border-zinc-800 divide-y divide-zinc-800"
      >
        <div
          :for={{id, scenario} <- @streams.scenarios}
          id={id}
          class="flex items-center justify-between gap-4 px-4 py-3 transition-colors hover:bg-zinc-900/50"
        >
          <div class="min-w-0">
            <.link
              patch={~p"/scenarios/#{scenario.id}"}
              class="font-semibold text-zinc-100 hover:text-white"
            >
              {scenario.name}
            </.link>
            <p class="truncate text-sm text-zinc-500">
              {length(scenario.rule_ids)} rule(s) · {map_size(scenario.facts)} fact(s)
            </p>
          </div>

          <div class="flex shrink-0 items-center gap-2">
            <.link patch={~p"/scenarios/#{scenario.id}"} class="btn btn-ghost btn-sm">Open</.link>

            <button
              type="button"
              phx-click="delete"
              value={scenario.id}
              data-confirm="Delete this scenario?"
              class="btn btn-error btn-sm"
            >
              Delete
            </button>
          </div>
        </div>

        <div id="scenarios-empty" class="hidden only:block px-4 py-12 text-center text-zinc-500">
          No scenarios yet. <.link patch={~p"/scenarios/new"} class="link">Create one</.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("delete", %{"value" => id}, socket) do
    case VerdictUI.get_scenario(id) do
      %VerdictUI.Scenario{} = scenario ->
        VerdictUI.delete_scenario(scenario)
        {:noreply, stream_delete(socket, :scenarios, scenario)}

      _ ->
        {:noreply, socket}
    end
  end

  defp stream_scenarios(socket) do
    stream(socket, :scenarios, VerdictUI.list_scenarios())
  end
end
