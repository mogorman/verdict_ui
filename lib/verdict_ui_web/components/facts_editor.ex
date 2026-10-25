defmodule VerdictUIWeb.Components.FactsEditor do
  @moduledoc """
  A generic key/value row editor (a list of `%{"name" => ..., "value" => ...}`
  rows, values as input strings).

  Pure presentational. Each row's inputs are named `<prefix>-<i>-name` /
  `<prefix>-<i>-value` and the remove button emits `remove_event`. The owning
  LiveView's form-level `phx-change` and `remove_event` handler drive state. Used
  for both runtime facts and event params.

  When `template_toggle` is set, each row also renders a checkbox named
  `<prefix>-<i>-template` (checked per `row["template"]`) to mark a value as an EEx
  template instead of plain JSON, and — when checked — a `<select>` named
  `<prefix>-<i>-type` (options from `template_types`) naming the `eex_<type>` marker
  the template is coerced to (per `row["type"]`).
  """
  use VerdictUIWeb, :html

  attr :rows, :list, required: true
  attr :prefix, :string, default: "fact"
  attr :remove_event, :string, default: "remove-fact"
  attr :change_event, :string, default: "fact"
  attr :key_placeholder, :string, default: "key"
  attr :value_placeholder, :string, default: "value (JSON: 40, true, [1,2])"
  attr :template_toggle, :boolean, default: false
  attr :template_types, :list, default: []

  def facts_editor(assigns) do
    ~H"""
    <div :for={{row, i} <- Enum.with_index(@rows)} class="flex items-center gap-2">
      <input
        name={"#{@prefix}-#{i}-name"}
        type="text"
        value={row["name"]}
        placeholder={@key_placeholder}
        class="w-32 input input-sm shrink-0"
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

      <select
        :if={@template_toggle and row["template"]}
        name={"#{@prefix}-#{i}-type"}
        class="select select-sm w-28 shrink-0"
        phx-change={@change_event}
      >
        <option :for={type <- @template_types} value={type} selected={row["type"] == type}>
          {type}
        </option>
      </select>

      <input
        id={"#{@prefix}-#{i}-value"}
        name={"#{@prefix}-#{i}-value"}
        type="text"
        value={row["value"]}
        placeholder={value_placeholder(row, @value_placeholder)}
        class="flex-1 min-w-0 input input-sm"
        phx-change={@change_event}
        phx-debounce="200"
        phx-hook=".JsonHint"
        data-jsonhint={if(row["template"], do: "false", else: "true")}
      />

      <button
        type="button"
        phx-click={@remove_event}
        value={i}
        aria-label="Remove row"
        class="btn btn-ghost btn-sm shrink-0"
      >
        ×
      </button>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".JsonHint">
      export default {
        mounted() {
          const el = this.el;
          const update = () => {
            if (el.dataset.jsonhint !== "true") {
              el.style.borderColor = "";
              return;
            }
            const v = el.value.trim();
            if (v === "") {
              el.style.borderColor = "";
              return;
            }
            let ok = false;
            try {
              JSON.parse(v);
              ok = true;
            } catch (_) {}
            el.style.borderColor = ok ? "#22c55e" : "#ef4444";
          };
          el.addEventListener("input", update);
          update();
        }
      }
    </script>
    """
  end

  # A template row's value is an EEx template string; a plain row is JSON.
  defp value_placeholder(%{"template" => true, "type" => type}, _default)
       when is_binary(type) do
    "EEx template → #{type}"
  end

  defp value_placeholder(_row, default), do: default
end
