defmodule VerdictUIWeb.RuleIndexLive do
  @moduledoc false
  use VerdictUIWeb, :live_view

  alias VerdictUI

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream_rules(socket), temporary_assigns: [rules: []]}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Rules
        <:actions>
          <.link patch={~p"/rules/new"} class="btn btn-primary btn-sm">New rule</.link>
        </:actions>
      </.header>

      <div
        id="rules"
        phx-update="stream"
        class="rounded-lg border border-zinc-800 divide-y divide-zinc-800"
      >
        <div
          :for={{id, rule} <- @streams.rules}
          id={id}
          class="flex items-center justify-between gap-4 px-4 py-3 transition-colors hover:bg-zinc-900/50"
        >
          <div class="min-w-0">
            <.link
              patch={~p"/rules/#{rule.id}/edit"}
              class="font-semibold text-zinc-100 hover:text-white"
            >
              {rule.name}
            </.link>
            <p class="text-sm text-zinc-500 truncate">
              <span>priority {rule.priority}</span>
              <span :if={rule.event && rule.event.type != ""}> · event {rule.event.type}</span>
            </p>
          </div>

          <div class="flex shrink-0 items-center gap-2">
            <.link patch={~p"/rules/#{rule.id}/test"} class="btn btn-ghost btn-sm">Test</.link>
            <.link patch={~p"/rules/#{rule.id}/edit"} class="btn btn-ghost btn-sm">Edit</.link>
            <button
              type="button"
              phx-click="delete"
              value={rule.id}
              data-confirm="Delete this rule?"
              class="btn btn-error btn-sm"
            >
              Delete
            </button>
          </div>
        </div>

        <div id="rules-empty" class="hidden only:block px-4 py-12 text-center text-zinc-500">
          No rules yet. <.link patch={~p"/rules/new"} class="link">Create one</.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("delete", %{"value" => id}, socket) do
    case VerdictUI.get_rule(id) do
      %VerdictUI.Rule{} = rule ->
        VerdictUI.delete_rule(rule)
        {:noreply, stream_delete(socket, :rules, rule)}

      _ ->
        {:noreply, socket}
    end
  end

  defp stream_rules(socket) do
    stream(socket, :rules, VerdictUI.list_rules())
  end
end
