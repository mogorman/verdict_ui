defmodule VerdictUI.ConditionTreeTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias VerdictUI.ConditionTree

  # all
  #   ├── leaf gameDuration equal 40
  #   └── any
  #         ├── leaf level >= 5
  #         └── not
  #               └── leaf muted equal true
  defp tree do
    %{
      "all" => [
        %{"fact" => "gameDuration", "operator" => "equal", "value" => 40},
        %{
          "any" => [
            %{"fact" => "level", "operator" => "greaterThanInclusive", "value" => 5},
            %{"not" => %{"fact" => "muted", "operator" => "equal", "value" => true}}
          ]
        }
      ]
    }
  end

  test "kind_of/1 classifies every node type" do
    t = tree()
    assert ConditionTree.kind_of(t) == :all
    assert ConditionTree.kind_of(ConditionTree.get_node(t, [0])) == :leaf
    assert ConditionTree.kind_of(ConditionTree.get_node(t, [1])) == :any
    assert ConditionTree.kind_of(ConditionTree.get_node(t, [1, 1])) == :not
    assert ConditionTree.kind_of(%{"condition" => "x"}) == :ref
    assert ConditionTree.kind_of(%{}) == :unknown
  end

  test "is_group?/1 and children_of/1" do
    t = tree()
    assert ConditionTree.is_group?(t)
    assert ConditionTree.is_group?(ConditionTree.get_node(t, [1, 1]))
    refute ConditionTree.is_group?(ConditionTree.get_node(t, [0]))
    assert length(ConditionTree.children_of(t)) == 2
    assert ConditionTree.children_of(ConditionTree.get_node(t, [0])) == []
    # a not node exposes its single child as a one-element list
    assert length(ConditionTree.children_of(ConditionTree.get_node(t, [1, 1]))) == 1
  end

  test "get_node/2 walks paths" do
    t = tree()
    assert ConditionTree.get_node(t, []) == t
    assert ConditionTree.get_node(t, [0])["fact"] == "gameDuration"
    assert ConditionTree.get_node(t, [1, 0])["fact"] == "level"
    assert ConditionTree.get_node(t, [1, 1])["not"]["fact"] == "muted"
    assert ConditionTree.get_node(t, [0, 0]) == nil
  end

  test "add_child/3 appends to a list group" do
    t = tree()
    updated = ConditionTree.add_child(t, [1], ConditionTree.build_leaf())
    assert length(ConditionTree.children_of(ConditionTree.get_node(updated, [1]))) == 3
    assert length(ConditionTree.children_of(updated)) == 2
    assert t == tree()
  end

  test "add_child/3 replaces the child of a not node" do
    t = tree()
    new_leaf = %{"fact" => "home", "operator" => "equal", "value" => false}
    updated = ConditionTree.add_child(t, [1, 1], new_leaf)
    assert ConditionTree.get_node(updated, [1, 1])["not"] == new_leaf
  end

  test "remove_node/2 removes a nested child" do
    updated = tree() |> ConditionTree.remove_node([1, 1])
    assert length(ConditionTree.children_of(ConditionTree.get_node(updated, [1]))) == 1
  end

  test "remove_node/2 removes a whole root child" do
    updated = tree() |> ConditionTree.remove_node([1])
    assert length(ConditionTree.children_of(updated)) == 1
    assert ConditionTree.get_node(updated, [0])["fact"] == "gameDuration"
  end

  test "update_node/3 edits a leaf without touching siblings" do
    updated =
      tree() |> ConditionTree.update_node([0], %{"value" => 30, "operator" => "greaterThan"})

    assert ConditionTree.get_node(updated, [0])["value"] == 30
    assert ConditionTree.get_node(updated, [0])["operator"] == "greaterThan"
    assert ConditionTree.get_node(updated, [1, 0])["fact"] == "level"
  end

  test "set_kind/3 swaps all and any, keeping children" do
    updated = tree() |> ConditionTree.set_kind([1], "all")
    node = ConditionTree.get_node(updated, [1])
    assert ConditionTree.kind_of(node) == :all
    assert length(ConditionTree.children_of(node)) == 2
    refute Map.has_key?(node, "any")
  end

  test "an edited tree still validates through VerdictUI.Rule.changeset/2" do
    base = %{
      "all" => [
        %{"fact" => "gameDuration", "operator" => "equal", "value" => 40}
      ]
    }

    edited =
      ConditionTree.add_child(base, [], %{
        "fact" => "team",
        "operator" => "in",
        "value" => ["A", "B"]
      })

    source = %{name: "edited", event: %{"type" => "t"}, conditions: edited}
    changeset = VerdictUI.Rule.changeset(%VerdictUI.Rule{}, source)
    assert changeset.valid?
    assert length(Ecto.Changeset.apply_changes(changeset).conditions.children) == 2
  end

  test "path string round-trips" do
    assert ConditionTree.to_path_string([]) == ""
    assert ConditionTree.to_path_string([1, 0, 2]) == "1.0.2"
    assert ConditionTree.parse_path("") == []
    assert ConditionTree.parse_path("1.0.2") == [1, 0, 2]
  end

  test "field name round-trips" do
    assert ConditionTree.field_name("", "fact") == "cond-fact"
    assert ConditionTree.parse_field_name("cond-fact") == {[], "fact"}
    assert ConditionTree.field_name("1.0", "value") == "cond-1.0-value"
    assert ConditionTree.parse_field_name("cond-1.0-value") == {[1, 0], "value"}
  end

  test "value parsing round-trips through the editor" do
    for {input, term} <- [
          {"", nil},
          {"40", 40},
          {"3.5", 3.5},
          {"true", true},
          {"[\"A\",\"B\"]", ["A", "B"]},
          {"home", "home"}
        ] do
      assert ConditionTree.parse_value(input) == term
      assert ConditionTree.value_to_input(term) == input
    end
  end
end
