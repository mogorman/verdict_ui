defmodule VerdictUI.ConditionTree do
  @moduledoc """
  Pure, path-based mutators for the condition tree stored in `VerdictUI.Rule.conditions`.

  A node is a string-keyed map in the engine's JSON form:

      %{"all" => [child, ...]}                 # every child truthy
      %{"any" => [child, ...]}                 # some child truthy
      %{"not" => child}                        # negation of its single child
      %{"condition" => "name"}                 # reference to a named condition
      %{"fact" => "f", "operator" => "op", "value" => v, "path" => "..."?, "params" => %{}}

  A node is addressed by a **path**: a list of child indices from the root
  (`[]` is the root; `[1, 0]` is the root's second child's first child). All
  functions are pure — the input tree is never mutated.
  """

  @doc "The kind of a node: `:all`, `:any`, `:not`, `:ref`, `:leaf` or `:unknown`."
  def kind_of(%{"all" => _}), do: :all
  def kind_of(%{"any" => _}), do: :any
  def kind_of(%{"not" => _}), do: :not
  def kind_of(%{"condition" => _}), do: :ref
  def kind_of(%{"fact" => _}), do: :leaf
  def kind_of(%{}), do: :unknown

  @doc "The list of children of a node ([] for leaves and refs)."
  def children_of(node) do
    cond do
      is_list(Map.get(node, "all")) -> Map.fetch!(node, "all")
      is_list(Map.get(node, "any")) -> Map.fetch!(node, "any")
      is_map(Map.get(node, "not")) -> [Map.fetch!(node, "not")]
      true -> []
    end
  end

  @doc "The node at `path` (nil if any index is out of range). `[]` is the root."
  def get_node(root, []), do: root

  def get_node(root, [i | rest]) do
    case root |> children_of() |> Enum.at(i) do
      nil -> nil
      child -> get_node(child, rest)
    end
  end

  @doc "Append `child` to the group at `path`. For a `not` node, replaces its child."
  def add_child(root, path, child) when is_map(child) do
    update_at(root, path, fn node ->
      case kind_of(node) do
        :not -> %{node | "not" => child}
        _ -> put_children(node, children_of(node) ++ [child])
      end
    end)
  end

  @doc "Remove the node at `path` (path must not be the root)."
  def remove_node(root, [_ | _] = path) do
    {parent_path, index} = {Enum.drop(path, -1), List.last(path)}
    update_at(root, parent_path, &put_children(&1, children_of(&1) |> List.delete_at(index)))
  end

  @doc "Merge `updates` (string-keyed) into the node at `path`."
  def update_node(root, path, updates) when is_map(updates) do
    update_at(root, path, &Map.merge(&1, updates))
  end

  @doc "Change a group's kind between `all` and `any`, preserving its children."
  def set_kind(root, path, kind) when kind in ["all", "any"] do
    update_at(root, path, fn node ->
      node |> Map.delete("all") |> Map.delete("any") |> Map.put(kind, children_of(node))
    end)
  end

  # --- builders -------------------------------------------------------------

  @doc "A new boolean group: `%{\"all\" => []}` or `%{\"any\" => []}`."
  def build_group("all"), do: %{"all" => []}
  def build_group("any"), do: %{"any" => []}

  @doc "A `not` node seeded with an empty leaf to fill in."
  def build_not, do: %{"not" => build_leaf()}

  @doc "An empty leaf to fill in."
  def build_leaf, do: %{"fact" => "", "operator" => "equal", "value" => nil}

  @doc "Decodes a dot-separated path string back into a list of integer indices."
  def parse_path(""), do: []

  def parse_path(string) when is_binary(string) do
    string |> String.split(".") |> Enum.map(&String.to_integer/1)
  end

  @doc "The input `name` for a leaf/ref field at `path` (a dot-separated string)."
  def field_name("", field), do: "cond-" <> field
  def field_name(path, field), do: "cond-#{path}-#{field}"

  @doc """
  Decodes a field input `name` (see `field_name/2`) back into `{path, field}`.
  `path` is a list of integer indices.
  """
  def parse_field_name("cond-" <> rest) do
    parts = String.split(rest, "-")
    field = List.last(parts)
    path = parts |> Enum.drop(-1) |> Enum.join(".") |> parse_path()
    {path, field}
  end

  @doc """
  Parses a value entered in the editor into a term: JSON scalars/arrays/objects
  decode to their native types, an empty string becomes `nil`, and anything
  that is not valid JSON is kept as a plain string.
  """
  def parse_value(""), do: nil

  def parse_value(value) when is_binary(value) do
    case VerdictUI.JSON.decode(value) do
      {:ok, decoded} -> decoded
      {:error, _} -> value
    end
  end

  @doc "Renders a stored value as text for the editor (the inverse of `parse_value/1`)."
  def value_to_input(nil), do: ""
  def value_to_input(value) when is_binary(value), do: value
  def value_to_input(value), do: VerdictUI.JSON.encode!(value)

  @doc "The sorted list of unique fact names referenced by leaf nodes in the tree."
  def fact_names(tree) do
    tree
    |> collect_facts()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # --- internals ------------------------------------------------------------

  defp collect_facts(node) do
    case kind_of(node) do
      :leaf -> [node["fact"]]
      :all -> children_of(node) |> Enum.flat_map(&collect_facts/1)
      :any -> children_of(node) |> Enum.flat_map(&collect_facts/1)
      :not -> children_of(node) |> Enum.flat_map(&collect_facts/1)
      _ -> []
    end
  end

  defp put_children(%{"all" => _} = node, list), do: %{node | "all" => list}
  defp put_children(%{"any" => _} = node, list), do: %{node | "any" => list}
  defp put_children(%{"not" => _} = node, list), do: %{node | "not" => List.first(list)}
  defp put_children(node, _), do: node

  defp update_at(root, [], fun), do: fun.(root)

  defp update_at(root, [i | rest], fun) do
    children = children_of(root)
    new_child = Enum.at(children, i) || %{}
    new_child = update_at(new_child, rest, fun)
    put_children(root, List.replace_at(children, i, new_child))
  end
end
