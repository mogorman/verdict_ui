defmodule VerdictUIWeb.Components.FactsEditor do
  @moduledoc """
  A generic key/value row editor (a list of `%{"name" => ..., "value" => ...}`
  rows, values as input strings).

  Pure presentational. Each row's inputs are named `<prefix>-<i>-name` /
  `<prefix>-<i>-value` and the remove button emits `remove_event`. The owning
  LiveView's form-level `phx-change` and `remove_event` handler drive state. Used
  for both runtime facts and event params.

  When `template_toggle` is set, each row also renders a checkbox named
  `<prefix>-<i>-template` (checked per `row["template"]`), letting the caller mark
  a value as an EEx template instead of plain JSON.
  """
  use VerdictUIWeb, :html

  attr :rows, :list, required: true
  attr :prefix, :string, default: "fact"
  attr :remove_event, :string, default: "remove-fact"
  attr :change_event, :string, default: "fact"
  attr :key_placeholder, :string, default: "key"
  attr :value_placeholder, :string, default: "value (JSON: 40, true, [1,2])"
  attr :template_toggle, :boolean, default: false

  def facts_editor(assigns) do
    ~H"""
    <div :for={{row, i} <- Enum.with_index(@rows)} class="flex items-center gap-2">
      <input
        name={"#{@prefix}-#{i}-name"}
        type="text"
        value={row["name"]}
        placeholder={@key_placeholder}
        class={if(@template_toggle, do: "w-1/4 input input-sm", else: "w-2/5 input input-sm")}
        phx-change={@change_event}
        phx-debounce="200"
      />
      <input
        name={"#{@prefix}-#{i}-value"}
        type="text"
        value={row["value"]}
        placeholder={@value_placeholder}
        class={if(@template_toggle, do: "w-2/3 input input-sm", else: "w-3/5 input input-sm")}
        phx-change={@change_event}
        phx-debounce="200"
      />
      <input
        :if={@template_toggle}
        name={"#{@prefix}-#{i}-template"}
        type="checkbox"
        checked={row["template"]}
        value="true"
        title="EEx template"
        class="checkbox checkbox-sm shrink-0"
        phx-change={@change_event}
      />

      <button
        type="button"
        phx-click={@remove_event}
        value={i}
        aria-label="Remove row"
        class="btn btn-ghost btn-sm"
      >
        ×
      </button>
    </div>
    """
  end
end
