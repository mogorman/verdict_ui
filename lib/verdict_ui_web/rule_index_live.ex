defmodule VerdictUIWeb.RuleIndexLive do
  @moduledoc false
  use VerdictUIWeb, :live_view

  alias VerdictUI

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> stream_rules()
      |> assign(:show_import, false)
      |> assign(:import_form, to_form(%{"source" => ""}))
      |> assign(:import_error, nil)
      |> allow_upload(:file, accept: [".json", "application/json"], max_entries: 1)

    {:ok, socket, temporary_assigns: [rules: []]}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Rules
        <:actions>
          <button type="button" phx-click="toggle-import" class="btn btn-ghost btn-sm">
            Import
          </button>
          <.link patch={~p"/rules/new"} class="btn btn-primary btn-sm">New rule</.link>
        </:actions>
      </.header>

      <.form
        :if={@show_import}
        for={@import_form}
        id="import-panel"
        phx-submit="import"
        class="mb-4 space-y-3 rounded-lg border border-zinc-800 bg-zinc-900/40 p-4"
      >
        <p class="label mb-0">Import rule</p>

        <.input
          field={@import_form[:source]}
          id="import-source"
          type="textarea"
          placeholder="Paste the rule JSON, or choose a .json file"
        />

        <input
          type="file"
          name="rule_file"
          id="import-file"
          phx-upload="file"
          accept=".json,application/json"
          class="file-input file-input-bordered file-input-sm w-full max-w-xs"
        />

        <div :if={@import_error} id="import-error" class="alert alert-error py-2 text-sm">
          {@import_error}
        </div>

        <div class="flex gap-2">
          <button
            type="submit"
            id="import-submit"
            class="btn btn-primary btn-sm"
            phx-disable-with="Importing…"
          >
            Import rule
          </button>
          <button type="button" phx-click="toggle-import" class="btn btn-ghost btn-sm">
            Cancel
          </button>
        </div>
      </.form>

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
            <a
              href={VerdictUI.Rule.export_href(rule)}
              download={rule.name <> ".json"}
              class="btn btn-ghost btn-sm"
            >
              Export
            </a>
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

  @impl true
  def handle_event("toggle-import", _params, socket) do
    {:noreply, assign(socket, show_import: !socket.assigns.show_import, import_error: nil)}
  end

  @impl true
  def handle_event("import", params, socket) do
    source =
      case params["rule_file"] do
        %{} = upload ->
          Phoenix.LiveView.consume_uploaded_entry(socket, upload, fn file_meta ->
            {:ok, File.read!(file_meta[:path])}
          end)

        _ ->
          params["source"]
      end
      |> to_string()
      |> String.trim()

    if source == "" do
      {:noreply, assign(socket, import_error: "Paste the rule JSON or choose a .json file.")}
    else
      import_rule(source, socket)
    end
  end

  # Decodes the JSON and creates a new rule. `VerdictUI.create_rule/1` delegates
  # to the engine's `changeset/2`, the inverse of the export's `to_map/1`, so an
  # exported file round-trips back in unchanged.
  defp import_rule(source, socket) do
    case VerdictUI.JSON.decode(source) do
      {:ok, map} when is_map(map) ->
        import_create(map, socket)

      {:ok, _other} ->
        {:noreply, assign(socket, import_error: "The JSON must be a rule object (a map).")}

      {:error, _} ->
        {:noreply, assign(socket, import_error: "Invalid JSON.")}
    end
  end

  defp import_create(map, socket) do
    # The `event` column is NOT NULL, so a rule without an event raises a
    # constraint error (not a changeset error) — rescue it into a clean message.
    result =
      try do
        VerdictUI.create_rule(map)
      rescue
        e -> {:error, "could not be saved (#{Exception.message(e)})"}
      end

    case result do
      {:ok, rule} ->
        {:noreply,
         socket
         |> stream_insert(:rules, rule)
         |> put_flash(:info, "Imported #{rule.name}.")
         |> assign(:show_import, false)
         |> assign(:import_form, to_form(%{"source" => ""}))
         |> assign(:import_error, nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, import_error: changeset_errors(changeset))}

      {:error, message} ->
        {:noreply, assign(socket, import_error: message)}
    end
  end

  defp changeset_errors(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _opts}} -> "#{field}: #{to_string(msg)}" end)
    |> Enum.join("\n")
  end

  defp stream_rules(socket) do
    stream(socket, :rules, VerdictUI.list_rules())
  end
end
