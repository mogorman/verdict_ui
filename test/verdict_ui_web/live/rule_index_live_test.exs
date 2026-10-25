defmodule VerdictUIWeb.RuleIndexLiveTest do
  @moduledoc false
  use VerdictUIWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias VerdictUI

  @rule_attrs %{
    name: "index-rule",
    priority: 1,
    event: %{"type" => "gameOver"},
    conditions: %{"all" => [%{"fact" => "a", "operator" => "equal", "value" => 1}]}
  }

  test "lists rules and deletes", %{conn: conn} do
    {:ok, rule} = VerdictUI.create_rule(@rule_attrs)
    {:ok, view, html} = live(conn, ~p"/rules")
    assert html =~ "index-rule"
    assert html =~ "gameOver"

    render_click(view, "delete", %{"value" => rule.id})
    refute VerdictUI.get_rule(rule.id)
  end

  test "shows empty state", %{conn: conn} do
    for rule <- VerdictUI.list_rules(), do: VerdictUI.delete_rule(rule)
    {:ok, _view, html} = live(conn, ~p"/rules")
    assert html =~ "No rules yet"
  end
end
