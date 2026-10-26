defmodule VerdictUIWeb.RuleFormLive do
  @moduledoc """
  Create and edit Verdict rules. The condition tree is edited live with
  `VerdictUIWeb.Components.ConditionEditor`; scalar fields (name, priority,
  event) submit with the form.
  """
  use VerdictUIWeb, :live_view

  alias Verdict.Evaluation
  alias VerdictUI
  alias VerdictUI.ConditionTree
  alias VerdictUIWeb.Components.{ConditionEditor, FactsEditor, JsonPathPicker}

  @operators Verdict.Operators.known()
  @eex_types Enum.map(Verdict.Template.marker_types(), &to_string/1)

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(:operators, @operators)
      |> assign(:eex_types, @eex_types)

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
      failure_event_type: "",
      failure_param_rows: [],
      conditions: %{"all" => []},
      sample_rows: [],
      picker: nil,
      changeset: nil,
      template_errors: []
    )
  end

  defp assign_for_rule(socket, rule) do
    event = rule.event
    failure_event = rule.failure_event

    assign(socket,
      mode: :edit,
      rule: rule,
      name: rule.name || "",
      priority: rule.priority || 1,
      event_type: event && event.type,
      param_rows: params_to_rows((event && event.params) || %{}),
      failure_event_type: failure_event && failure_event.type,
      failure_param_rows: params_to_rows((failure_event && failure_event.params) || %{}),
      conditions: conditions_to_map(rule.conditions),
      sample_rows: sample_facts_to_rows(rule.sample_facts),
      picker: nil,
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

  def handle_event("pick-path", params, socket) do
    %{"path" => path, "fact" => fact} = payload(params)
    {:noreply, assign(socket, picker: %{"path" => path, "fact" => fact})}
  end

  def handle_event("pick-node", %{"value" => jsonpath}, socket) do
    tree =
      ConditionTree.update_node(
        socket.assigns.conditions,
        ConditionTree.parse_path(socket.assigns.picker["path"]),
        %{"path" => jsonpath}
      )

    {:noreply, assign(socket, conditions: tree, picker: nil)}
  end

  def handle_event("picker-paste", %{"sample" => raw}, socket) do
    if String.trim(raw || "") == "" do
      {:noreply, socket}
    else
      fact = socket.assigns.picker["fact"]

      {:noreply,
       assign(socket, sample_rows: upsert_sample_row(socket.assigns.sample_rows, fact, raw))}
    end
  end

  def handle_event("close-picker", _params, socket), do: {:noreply, assign(socket, picker: nil)}

  def handle_event("add-sfact", _params, socket) do
    {:noreply, assign(socket, sample_rows: socket.assigns.sample_rows ++ [blank_sample_row()])}
  end

  def handle_event("remove-sfact", %{"value" => idx}, socket) do
    i = String.to_integer(idx)

    {:noreply,
     assign(socket, sample_rows: List.delete_at(socket.assigns.sample_rows, i), picker: nil)}
  end

  def handle_event("sfact", params, socket) do
    name = changed_field(params)
    rows = socket.assigns.sample_rows

    case String.split(name, "-") do
      ["sfact", idx, field] when field in ["name", "value"] ->
        value = Map.get(params, name)
        i = String.to_integer(idx)
        rows = List.replace_at(rows, i, Map.put(Enum.at(rows, i), field, value))
        {:noreply, assign(socket, sample_rows: rows, picker: nil)}

      _ ->
        {:noreply, socket}
    end
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
       failure_event_type: Map.get(rule, "failure_event_type", socket.assigns.failure_event_type),
       priority: priority
     )}
  end

  def handle_event("add-param", _params, socket),
    do: {:noreply, assign(socket, param_rows: socket.assigns.param_rows ++ [blank_param_row()])}

  def handle_event("add-fparam", _params, socket),
    do:
      {:noreply,
       assign(socket,
         failure_param_rows: socket.assigns.failure_param_rows ++ [blank_param_row()]
       )}

  def handle_event("remove-param", %{"value" => idx}, socket) do
    i = String.to_integer(idx)
    {:noreply, assign(socket, param_rows: List.delete_at(socket.assigns.param_rows, i))}
  end

  def handle_event("remove-fparam", %{"value" => idx}, socket) do
    i = String.to_integer(idx)

    {:noreply,
     assign(socket, failure_param_rows: List.delete_at(socket.assigns.failure_param_rows, i))}
  end

  def handle_event("param", params, socket),
    do: param_change(socket, params, "param", :param_rows)

  def handle_event("fparam", params, socket),
    do: param_change(socket, params, "fparam", :failure_param_rows)

  def handle_event("save", %{"rule" => rule}, socket) do
    params = params_map(socket.assigns.param_rows)
    failure_params = params_map(socket.assigns.failure_param_rows)

    template_errors =
      [params, failure_params]
      |> Enum.flat_map(fn p ->
        case Verdict.Template.validate(p) do
          :ok -> []
          {:error, messages} -> messages
        end
      end)

    if template_errors == [] do
      attrs = %{
        name: rule["name"],
        priority: rule["priority"],
        event: %{type: rule["event_type"], params: params},
        failure_event: failure_event_attrs(rule["failure_event_type"], failure_params),
        conditions: socket.assigns.conditions,
        sample_facts: sample_facts_map(socket.assigns.sample_rows)
      }

      case socket.assigns.mode do
        :new -> save(:new, attrs, socket)
        :edit -> save(:edit, attrs, socket)
      end
    else
      {:noreply, assign(socket, template_errors: template_errors, changeset: nil)}
    end
  end

  # A failure event is only sent when a type is given; an empty type omits it so
  # the rule keeps (or has) no failure event.
  defp failure_event_attrs(nil, _params), do: nil
  defp failure_event_attrs("", _params), do: nil
  defp failure_event_attrs(type, params), do: %{type: type, params: params}

  defp blank_param_row(),
    do: %{"name" => "", "value" => "", "template" => false, "type" => "string"}

  defp param_change(socket, params, prefix, rows_field) do
    name = changed_field(params)
    rows = Map.get(socket.assigns, rows_field)

    case String.split(name, "-") do
      [^prefix, idx, "template"] ->
        i = String.to_integer(idx)
        row = Enum.at(rows, i)
        checked = Map.has_key?(params, name)

        {:noreply,
         assign(
           socket,
           rows_field,
           List.replace_at(rows, i, Map.put(row, "template", checked))
         )}

      [^prefix, idx, field] ->
        value = Map.get(params, name)
        i = String.to_integer(idx)
        row = Enum.at(rows, i)

        {:noreply,
         assign(socket, rows_field, List.replace_at(rows, i, Map.put(row, field, value)))}

      _ ->
        {:noreply, socket}
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
      case eex_marker(value) do
        nil ->
          %{
            "name" => to_string(name),
            "value" => ConditionTree.value_to_input(value),
            "template" => false,
            "type" => "string"
          }

        {type, template} ->
          %{"name" => to_string(name), "value" => template, "template" => true, "type" => type}
      end
    end)
  end

  defp params_map(rows) do
    rows
    |> Enum.reject(&(&1["name"] in [nil, ""]))
    |> Enum.map(fn row -> {row["name"], param_value(row)} end)
    |> Map.new()
  end

  # A template row keeps its value as a raw EEx string, tagged with the selected
  # `eex_<type>` marker; a plain row parses JSON.
  defp param_value(row) do
    if row["template"],
      do: %{"eex_#{row["type"]}" => row["value"]},
      else: ConditionTree.parse_value(row["value"])
  end

  # A single-key map with a binary value named `eex_<type>` is a typed EEx marker;
  # returns `{type, template}`, or `nil` for a non-marker value.
  defp eex_marker(%{} = map) when map_size(map) == 1 do
    [{key, value}] = Map.to_list(map)

    if is_binary(value) do
      type = to_string(key) |> String.replace_prefix("eex_", "")
      if type in @eex_types, do: {type, value}
    end
  end

  defp eex_marker(_), do: nil

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

  # --- sample facts + JSONPath previews ----------------------------------------

  defp blank_sample_row(), do: %{"name" => "", "value" => ""}

  defp sample_facts_map(rows) do
    rows
    |> Enum.reject(&(&1["name"] in [nil, ""]))
    |> Enum.map(&{&1["name"], ConditionTree.parse_value(&1["value"])})
    |> Map.new()
  end

  defp sample_facts_to_rows(facts) do
    (facts || %{})
    |> Enum.map(fn {name, value} ->
      %{"name" => to_string(name), "value" => ConditionTree.value_to_input(value)}
    end)
  end

  defp upsert_sample_row(rows, fact, raw) do
    row = %{"name" => fact, "value" => raw}

    case Enum.find_index(rows, &(&1["name"] == fact)) do
      nil -> rows ++ [row]
      i -> List.replace_at(rows, i, row)
    end
  end

  defp fact_names(sample_map, conditions) do
    (Map.keys(sample_map) ++ ConditionTree.fact_names(conditions))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # A `{leaf path string => resolved value}` map for every leaf that has both a
  # `path` and a sample fact, so the editor can show a live preview resolved by
  # the engine itself.
  defp leaf_previews(conditions, sample_map), do: walk_previews(conditions, "", sample_map)

  defp walk_previews(node, path, sample_map) do
    case ConditionTree.kind_of(node) do
      :leaf ->
        if is_binary(node["path"]) and node["path"] != "" and is_binary(node["fact"]) do
          case Map.fetch(sample_map, node["fact"]) do
            {:ok, sample} -> %{path => Evaluation.resolve_path(sample, node["path"])}
            :error -> %{}
          end
        else
          %{}
        end

      kind when kind in [:all, :any, :not] ->
        node
        |> ConditionTree.children_of()
        |> Enum.with_index()
        |> Enum.reduce(%{}, fn {child, i}, acc ->
          Map.merge(acc, walk_previews(child, child_preview_path(path, i), sample_map))
        end)

      _ ->
        %{}
    end
  end

  defp child_preview_path("", i), do: "#{i}"
  defp child_preview_path(path, i), do: "#{path}.#{i}"

  @impl true
  def render(assigns) do
    sample_map = sample_facts_map(assigns.sample_rows)

    assigns =
      assigns
      |> assign(:sample_map, sample_map)
      |> assign(:path_previews, leaf_previews(assigns.conditions, sample_map))
      |> assign(:fact_names, fact_names(sample_map, assigns.conditions))

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
            template_types={@eex_types}
          />

          <p :if={@param_rows == []} class="mt-1 text-xs text-base-content/50">
            Optional. Emitted with the event when it fires.
          </p>

          <p class="mt-1 text-xs text-base-content/50">
            Check a row's box to store its value as an EEx template string (stored as
            eex_string) — reference a fact by name to interpolate it.
          </p>
        </div>

        <.input
          name="rule[failure_event_type]"
          type="text"
          label="Failure event type"
          value={@failure_event_type}
          placeholder="e.g. notifyFouledOut (optional)"
          phx-change="scalar"
        />

        <div>
          <div class="mb-1 flex items-center justify-between">
            <p class="label mb-0">Failure event params</p>
            <button type="button" phx-click="add-fparam" class="btn btn-ghost btn-xs">
              + param
            </button>
          </div>

          <FactsEditor.facts_editor
            rows={@failure_param_rows}
            prefix="fparam"
            remove_event="remove-fparam"
            change_event="fparam"
            key_placeholder="param key"
            value_placeholder="value (JSON)"
            template_toggle
            template_types={@eex_types}
          />

          <p :if={@failure_param_rows == []} class="mt-1 text-xs text-base-content/50">
            Optional. Emitted only when the rule does not fire.
          </p>
        </div>

        <div>
          <div class="mb-1 flex items-center justify-between">
            <p class="label mb-0">Sample facts</p>
            <button type="button" phx-click="add-sfact" class="btn btn-ghost btn-xs">
              + sample
            </button>
          </div>

          <FactsEditor.facts_editor
            rows={@sample_rows}
            prefix="sfact"
            remove_event="remove-sfact"
            change_event="sfact"
            key_placeholder="fact name"
            value_placeholder="sample JSON (e.g. an object)"
          />

          <p :if={@sample_rows == []} class="mt-1 text-xs text-base-content/50">
            Optional. Paste a sample JSON value for a fact so you can pick JSONPaths into it
            from the conditions below.
          </p>
        </div>

        <div>
          <p class="label mb-1">Conditions</p>

          <datalist id="fact-names">
            <option :for={name <- @fact_names} value={name} />
          </datalist>

          <ConditionEditor.node_editor
            node={@conditions}
            path=""
            operators={@operators}
            previews={@path_previews}
          />

          <JsonPathPicker.picker
            :if={@picker}
            fact={@picker["fact"]}
            sample={Map.get(@sample_map, @picker["fact"])}
          />
        </div>

        <details class="group">
          <summary class="cursor-pointer text-sm text-base-content/70 hover:text-base-content">
            JSON preview
          </summary>
          <pre class="mt-2 overflow-auto rounded-md bg-base-200 p-3 text-xs">
            <code phx-no-curly-interpolation><%= preview_json(@name, @priority, @event_type, params_map(@param_rows), @failure_event_type, params_map(@failure_param_rows), @conditions) %></code>
          </pre>
        </details>

        <div class="flex gap-2">
          <.button phx-disable-with="Saving…">Save rule</.button>
          <a
            :if={@mode == :edit}
            href={VerdictUI.Rule.export_href(@rule)}
            download={@rule.name <> ".json"}
            class="btn btn-ghost"
          >
            Export JSON
          </a>
        </div>
      </form>
    </Layouts.app>
    """
  end

  defp preview_json(
         name,
         priority,
         event_type,
         params,
         failure_event_type,
         failure_params,
         conditions
       ) do
    event = %{"type" => event_type}
    event = if params == %{}, do: event, else: Map.put(event, "params", params)

    base = %{"name" => name, "priority" => priority, "event" => event, "conditions" => conditions}
    base = if priority in [nil, 1], do: Map.delete(base, "priority"), else: base

    base =
      if failure_event = build_event_map(failure_event_type, failure_params),
        do: Map.put(base, "failure_event", failure_event),
        else: base

    Jason.encode!(base, pretty: true)
  end

  defp build_event_map(nil, _params), do: nil
  defp build_event_map("", _params), do: nil

  defp build_event_map(type, params) do
    event = %{"type" => type}
    if params == %{}, do: event, else: Map.put(event, "params", params)
  end
end
