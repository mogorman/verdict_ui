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

  test "shows an Export link per rule", %{conn: conn} do
    VerdictUI.create_rule(@rule_attrs)
    {:ok, _view, html} = live(conn, ~p"/rules")
    assert html =~ "data:application/json;base64,"
    assert html =~ "index-rule.json"
  end

  test "import panel is hidden until toggled", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rules")
    refute has_element?(view, "#import-panel")
    render_click(view, "toggle-import")
    assert has_element?(view, "#import-panel")
  end

  test "imports a rule from pasted JSON", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rules")
    render_click(view, "toggle-import")

    json =
      VerdictUI.JSON.encode!(%{
        "name" => "imported-rule",
        "event" => %{"type" => "importedEvent"},
        "conditions" => %{"all" => [%{"fact" => "a", "operator" => "equal", "value" => 2}]}
      })

    render_submit(view, "import", %{"source" => json})
    assert has_element?(view, "a", "imported-rule")
    refute has_element?(view, "#import-panel")
  end

  test "import rejects invalid JSON", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rules")
    render_click(view, "toggle-import")
    render_submit(view, "import", %{"source" => "{not json"})
    assert has_element?(view, "#import-error", "Invalid JSON.")
  end

  test "import rejects a non-object JSON", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rules")
    render_click(view, "toggle-import")
    render_submit(view, "import", %{"source" => "[1, 2, 3]"})
    assert has_element?(view, "#import-error", "rule object")
  end

  test "import rejects a rule that fails validation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rules")
    render_click(view, "toggle-import")
    render_submit(view, "import", %{"source" => VerdictUI.JSON.encode!(%{"name" => "x"})})
    assert has_element?(view, "#import-error")
  end
end
