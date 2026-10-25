defmodule VerdictUIWeb.RuleFormLive do
  @moduledoc """
  Create and edit Verdict rules. The condition tree is edited live with
  `VerdictUIWeb.Components.ConditionEditor`; scalar fields (name, priority,
  event) submit with the form.
  """
  use VerdictUIWeb, :live_view

  alias VerdictUI
  alias VerdictUI.ConditionTree
  alias VerdictUIWeb.Components.{ConditionEditor, FactsEditor}

  @operators Verdict.Operators.known()

  @impl true
  def mount(params, _session, socket) do
    socket = assign(socket, :operators, @operators)

    case params do
      %{"id" => id} ->
        case VerdictUI.get_rule(id) do
          %VerdictUI.Rule{} = rule ->
            {:ok, assign_for_rule(socket, rule)}

          nil ->
            {:ok,
             socket
             |> assign_for_new()
             |> put_flash(:error, "Rule not found.")
             |> push_navigate(to: ~p"/rules/new")}
        end

      _ ->
        {:ok, assign_for_new(socket)}
    end
  end

  defp assign_for_new(socket) do
    assign(socket,
      mode: :new,
      rule: %VerdictUI.Rule{},
      name: "",
      priority: 1,
      event_type: "",
      param_rows: [],
      conditions: %{"all" => []},
      changeset: nil,
      template_errors: []
    )
  end

  defp assign_for_rule(socket, rule) do
    event = rule.event

    assign(socket,
      mode: :edit,
      rule: rule,
      name: rule.name || "",
      priority: rule.priority || 1,
      event_type: event && event.type,
      param_rows: params_to_rows((event && event.params) || %{}),
      conditions: conditions_to_map(rule.conditions),
      changeset: nil,
      template_errors: []
    )
  end

  @impl true
  def handle_event("cond:add", params, socket) do
    %{"path" => path, "kind" => kind} = payload(params)

    tree =
      ConditionTree.add_child(
        socket.assigns.conditions,
        ConditionTree.parse_path(path),
        build_node(kind)
      )

    {:noreply, assign(socket, conditions: tree)}
  end

  def handle_event("cond:remove", params, socket) do
    %{"path" => path} = payload(params)
    tree = ConditionTree.remove_node(socket.assigns.conditions, ConditionTree.parse_path(path))
    {:noreply, assign(socket, conditions: tree)}
  end

  def handle_event("cond:kind", params, socket) do
    %{"path" => path, "kind" => kind} = payload(params)
    tree = ConditionTree.set_kind(socket.assigns.conditions, ConditionTree.parse_path(path), kind)
    {:noreply, assign(socket, conditions: tree)}
  end

  def handle_event("cond:field", params, socket) do
    name = changed_field(params)
    raw = Map.get(params, name)
    {path, field} = ConditionTree.parse_field_name(name)
    value = if field == "value", do: ConditionTree.parse_value(raw), else: raw
    tree = ConditionTree.update_node(socket.assigns.conditions, path, %{field => value})
    {:noreply, assign(socket, conditions: tree)}
  end

  # Keeps the name/priority/event assigns in sync with the scalar inputs so the
  # JSON preview stays current (the form itself submits the same values on save).
  def handle_event("scalar", params, socket) do
    rule = params["rule"] || %{}

    priority =
      case Map.get(rule, "priority") do
        nil ->
          socket.assigns.priority

        p ->
          case Integer.parse(p) do
            {n, _} -> n
            :error -> socket.assigns.priority
          end
      end

    {:noreply,
     assign(socket,
       name: Map.get(rule, "name", socket.assigns.name),
       event_type: Map.get(rule, "event_type", socket.assigns.event_type),
       priority: priority
     )}
  end

  def handle_event("add-param", _params, socket) do
    {:noreply,
     assign(
       socket,
       param_rows:
         socket.assigns.param_rows ++ [%{"name" => "", "value" => "", "template" => false}]
     )}
  end

  def handle_event("remove-param", %{"value" => idx}, socket) do
    i = String.to_integer(idx)
    {:noreply, assign(socket, param_rows: List.delete_at(socket.assigns.param_rows, i))}
  end

  def handle_event("param", params, socket) do
    name = changed_field(params)

    case String.split(name, "-") do
      ["param", idx, "template"] ->
        i = String.to_integer(idx)
        row = Enum.at(socket.assigns.param_rows, i)
        checked = Map.has_key?(params, name)

        {:noreply,
         assign(socket,
           param_rows:
             List.replace_at(socket.assigns.param_rows, i, Map.put(row, "template", checked))
         )}

      ["param", idx, field] ->
        value = Map.get(params, name)
        i = String.to_integer(idx)
        row = Enum.at(socket.assigns.param_rows, i)

        {:noreply,
         assign(socket,
           param_rows: List.replace_at(socket.assigns.param_rows, i, Map.put(row, field, value))
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("save", %{"rule" => rule}, socket) do
    params = params_map(socket.assigns.param_rows)

    case Verdict.Template.validate(params) do
      :ok ->
        attrs = %{
          name: rule["name"],
          priority: rule["priority"],
          event: %{type: rule["event_type"], params: params},
          conditions: socket.assigns.conditions
        }

        case socket.assigns.mode do
          :new -> save(:new, attrs, socket)
          :edit -> save(:edit, attrs, socket)
        end

      {:error, messages} ->
        {:noreply, assign(socket, template_errors: messages, changeset: nil)}
    end
  end

  defp save(:new, attrs, socket) do
    case VerdictUI.create_rule(attrs) do
      {:ok, rule} -> redirect_to(rule, socket)
      {:error, changeset} -> {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp save(:edit, attrs, socket) do
    case VerdictUI.update_rule(socket.assigns.rule, attrs) do
      {:ok, rule} -> redirect_to(rule, socket)
      {:error, changeset} -> {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp redirect_to(rule, socket) do
    {:noreply,
     socket |> put_flash(:info, "Rule saved.") |> push_navigate(to: ~p"/rules/#{rule.id}/edit")}
  end

  defp build_node("leaf"), do: ConditionTree.build_leaf()
  defp build_node("all"), do: ConditionTree.build_group("all")
  defp build_node("any"), do: ConditionTree.build_group("any")
  defp build_node("not"), do: ConditionTree.build_not()

  defp params_to_rows(params) do
    Enum.map(params, fn {name, value} ->
      case eex_template(value) do
        nil ->
          %{
            "name" => to_string(name),
            "value" => ConditionTree.value_to_input(value),
            "template" => false
          }

        template ->
          %{"name" => to_string(name), "value" => template, "template" => true}
      end
    end)
  end

  defp params_map(rows) do
    rows
    |> Enum.reject(&(&1["name"] in [nil, ""]))
    |> Enum.map(fn row -> {row["name"], param_value(row)} end)
    |> Map.new()
  end

  # A template row keeps its value as a raw EEx string; a plain row parses JSON.
  defp param_value(row) do
    if row["template"],
      do: %{"eex_string" => row["value"]},
      else: ConditionTree.parse_value(row["value"])
  end

  # A value shaped `%{eex_string: "…"}` (atom or string key) is an EEx template.
  defp eex_template(%{eex_string: template}) when is_binary(template), do: template
  defp eex_template(%{"eex_string" => template}) when is_binary(template), do: template
  defp eex_template(_), do: nil

  # Decodes a phx-click `value` payload (a JSON string, or an already-decoded
  # map) into a string-keyed map.
  defp payload(params) do
    case params["value"] do
      nil -> Map.new(params)
      s when is_binary(s) -> s |> Jason.decode!() |> Map.new()
      m when is_map(m) -> Map.new(m)
    end
  end

  # A change event's params carry the changed field plus every other form input
  # (the latter `_unused_`-prefixed). `_target` names the field that actually
  # changed; tests that post a bare params map omit it, so fall back to the
  # first real key.
  defp changed_field(%{"_target" => [t]}) when is_binary(t), do: t

  defp changed_field(params) do
    params |> Map.delete("_target") |> Map.keys() |> hd()
  end

  defp conditions_to_map(cond) when is_struct(cond, Verdict.Condition),
    do: Verdict.Types.Condition.to_map(cond)

  defp conditions_to_map(map) when is_map(map), do: map
  defp conditions_to_map(_), do: %{"all" => []}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {if @mode == :new, do: "New rule", else: "Edit rule"}
        <:actions>
          <.link patch={~p"/"} class="btn btn-ghost btn-sm">Cancel</.link>
        </:actions>
      </.header>

      <div :if={@changeset} id="save-errors" class="alert alert-error mb-4">
        <p :for={{field, {msg, _opts}} <- @changeset.errors} class="text-sm">
          <span class="font-semibold">{field}:</span> {msg}
        </p>
      </div>

      <div :if={@template_errors != []} id="template-errors" class="alert alert-error mb-4">
        <p :for={msg <- @template_errors} class="text-sm">{msg}</p>
      </div>

      <form id="rule-form" phx-submit="save" class="space-y-6">
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-[1fr_6rem]">
          <.input
            name="rule[name]"
            type="text"
            label="Name"
            value={@name}
            placeholder="e.g. fouled-out"
            phx-change="scalar"
          />
          <.input
            name="rule[priority]"
            type="number"
            label="Priority"
            value={@priority}
            phx-change="scalar"
          />
        </div>

        <.input
          name="rule[event_type]"
          type="text"
          label="Event type"
          value={@event_type}
          placeholder="e.g. fouledOut"
          phx-change="scalar"
        />

        <div>
          <div class="mb-1 flex items-center justify-between">
            <p class="label mb-0">Event params</p>
            <button type="button" phx-click="add-param" class="btn btn-ghost btn-xs">
              + param
            </button>
          </div>

          <FactsEditor.facts_editor
            rows={@param_rows}
            prefix="param"
            remove_event="remove-param"
            change_event="param"
            key_placeholder="param key"
            value_placeholder="value (JSON)"
            template_toggle
          />

          <p :if={@param_rows == []} class="mt-1 text-xs text-base-content/50">
            Optional. Emitted with the event when it fires.
          </p>

          <p class="mt-1 text-xs text-base-content/50">
            Check a row's box to store its value as an EEx template string (stored as
            eex_string) — reference a fact by name to interpolate it.
          </p>
        </div>

        <div>
          <p class="label mb-1">Conditions</p>
          <ConditionEditor.node_editor node={@conditions} path="" operators={@operators} />
        </div>

        <details class="group">
          <summary class="cursor-pointer text-sm text-base-content/70 hover:text-base-content">
            JSON preview
          </summary>
          <pre class="mt-2 overflow-auto rounded-md bg-base-200 p-3 text-xs">
            <code phx-no-curly-interpolation><%= preview_json(@name, @priority, @event_type, params_map(@param_rows), @conditions) %></code>
          </pre>
        </details>

        <div class="flex gap-2">
          <.button phx-disable-with="Saving…">Save rule</.button>
        </div>
      </form>
    </Layouts.app>
    """
  end

  defp preview_json(name, priority, event_type, params, conditions) do
    event = %{"type" => event_type}
    event = if params == %{}, do: event, else: Map.put(event, "params", params)

    base = %{"name" => name, "priority" => priority, "event" => event, "conditions" => conditions}
    base = if priority in [nil, 1], do: Map.delete(base, "priority"), else: base
    Jason.encode!(base, pretty: true)
  end
end
