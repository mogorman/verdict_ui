defmodule VerdictUIWeb.Components.ConditionEditor do
  @moduledoc """
  A recursive, path-addressed editor for a rule's condition tree.

  It is a pure presentational function component: it renders a node (and its
  children recursively) and emits `phx-click` / `phx-change` events carrying the
  node's dot-separated `path` (`""` for the root). The owning LiveView mutates
  its `:conditions` assign with `VerdictUI.ConditionTree` and re-renders.

  Events emitted:

    * `cond:add`   `value=%{"path" => p, "kind" => "leaf"|"all"|"any"|"not"}`
    * `cond:remove` `value=%{"path" => p}`
    * `cond:kind`  `value=%{"path" => p, "kind" => "all"|"any"}`
    * `cond:field` (phx-change) — the changed input's `name` is
      `VerdictUI.ConditionTree.field_name/2` (path + field).
  """
  use VerdictUIWeb, :html

  alias VerdictUI.ConditionTree

  attr :node, :map, required: true
  attr :path, :string, required: true
  attr :operators, :list, required: true

  def node_editor(assigns) do
    kind = ConditionTree.kind_of(assigns.node)
    children = ConditionTree.children_of(assigns.node)

    assigns =
      assigns
      |> assign(:kind, kind)
      |> assign(:children, children)
      |> assign(:is_root, assigns.path == "")
      |> assign(:id, "cond-#{assigns.path}")
      |> assign(:label, label(kind))
      |> assign(:accent, accent(kind))

    ~H"""
    <div id={@id} class="rounded-md border border-base-300 border-l-4 #{@accent} bg-base-100 p-3">
      <div class="flex flex-wrap items-center gap-2">
        <span class="badge badge-ghost font-mono text-xs uppercase">{@label}</span>

        <div :if={@kind in [:all, :any]} class="flex flex-wrap gap-1">
          <button
            type="button"
            class="btn btn-ghost btn-xs"
            phx-click="cond:kind"
            value={val(%{"path" => @path, "kind" => if(@kind == :all, do: "any", else: "all")})}
          >
            → {if(@kind == :all, do: "ANY", else: "ALL")}
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-xs"
            phx-click="cond:add"
            value={val(%{"path" => @path, "kind" => "leaf"})}
          >+ condition</button>
          <button
            type="button"
            class="btn btn-ghost btn-xs"
            phx-click="cond:add"
            value={val(%{"path" => @path, "kind" => "all"})}
          >+ all</button>
          <button
            type="button"
            class="btn btn-ghost btn-xs"
            phx-click="cond:add"
            value={val(%{"path" => @path, "kind" => "any"})}
          >+ any</button>
          <button
            type="button"
            class="btn btn-ghost btn-xs"
            phx-click="cond:add"
            value={val(%{"path" => @path, "kind" => "not"})}
          >+ not</button>
        </div>

        <span :if={not @is_root} class="ml-auto">
          <button
            type="button"
            class="btn btn-ghost btn-xs text-error hover:bg-error/10"
            phx-click="cond:remove"
            value={val(%{"path" => @path})}
            aria-label="Remove condition"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </span>
      </div>

      <div :if={@kind in [:all, :any]} class="mt-3 space-y-2 pl-3">
        <p :if={@children == []} class="text-sm text-base-content/50">
          No conditions yet — add one above.
        </p>
        <div :for={{child, i} <- Enum.with_index(@children)}>
          <.node_editor node={child} path={child_path(@path, i)} operators={@operators} />
        </div>
      </div>

      <div :if={@kind == :not} class="mt-3 pl-3">
        <.node_editor
          :if={child = List.first(@children)}
          node={child}
          path={child_path(@path, 0)}
          operators={@operators}
        />
      </div>

      <div :if={@kind == :leaf} class="mt-3 grid grid-cols-1 gap-2 sm:grid-cols-[11rem_11rem_1fr]">
        <.input
          type="text"
          name={ConditionTree.field_name(@path, "fact")}
          value={@node["fact"]}
          placeholder="fact (e.g. score)"
          phx-change="cond:field"
          phx-debounce="300"
          class="font-mono text-sm"
        />
        <.input
          type="select"
          name={ConditionTree.field_name(@path, "operator")}
          value={@node["operator"]}
          options={operator_options(@node["operator"], @operators)}
          phx-change="cond:field"
        />
        <.input
          type="text"
          name={ConditionTree.field_name(@path, "value")}
          value={ConditionTree.value_to_input(@node["value"])}
          placeholder="value (JSON: 40, true, a list)"
          phx-change="cond:field"
          phx-debounce="300"
          class="font-mono text-sm"
        />
      </div>

      <div :if={@kind == :ref} class="mt-3">
        <.input
          type="text"
          name={ConditionTree.field_name(@path, "condition")}
          value={@node["condition"]}
          placeholder="named condition"
          phx-change="cond:field"
          phx-debounce="300"
          class="font-mono text-sm"
        />
      </div>
    </div>
    """
  end

  defp child_path("", i), do: "#{i}"
  defp child_path(path, i), do: "#{path}.#{i}"

  # phx-click `value` attributes must be HTML-safe, so the payload is a JSON
  # string; the client forwards it and the LiveView decodes it (see `payload/1`).
  defp val(map), do: Jason.encode!(map)

  defp operator_options(current, operators) do
    opts = Enum.map(operators, &{&1, &1})

    if is_binary(current) and current != "" and not Enum.member?(operators, current) do
      [{current, current} | opts]
    else
      opts
    end
  end

  defp label(:all), do: "all"
  defp label(:any), do: "any"
  defp label(:not), do: "not"
  defp label(:leaf), do: "condition"
  defp label(:ref), do: "ref"
  defp label(_), do: "?"

  defp accent(:all), do: "border-l-success"
  defp accent(:any), do: "border-l-info"
  defp accent(:not), do: "border-l-warning"
  defp accent(:ref), do: "border-l-primary"
  defp accent(_), do: "border-l-base-300"
end
