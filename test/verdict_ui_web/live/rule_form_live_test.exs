defmodule VerdictUIWeb.RuleFormLiveTest do
  @moduledoc false
  use VerdictUIWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias VerdictUI

  @attrs %{
    name: "fouled-out",
    priority: 5,
    event: %{"type" => "fouledOut"},
    conditions: %{
      "all" => [
        %{"fact" => "gameDuration", "operator" => "equal", "value" => 40},
        %{"fact" => "personalFoulCount", "operator" => "greaterThanInclusive", "value" => 5}
      ]
    }
  }

  test "renders a new rule form with an empty all group", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/rules/new")
    assert render(view) =~ "New rule"
    assert has_element?(view, "#rule-form")
    assert render(view) =~ "No conditions yet"
  end

  test "creates a rule by building a condition and saving", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/rules/new")

    view |> element("button", "+ condition") |> render_click()
    assert has_element?(view, "input[name=cond-0-fact]")

    view
    |> element("input[name=cond-0-fact]")
    |> render_change(%{"cond-0-fact" => "gameDuration"})

    view |> element("input[name=cond-0-value]") |> render_change(%{"cond-0-value" => "40"})

    view
    |> form("#rule-form", %{rule: %{name: "duration", priority: 1, event_type: "overtime"}})
    |> render_submit()

    [rule] = VerdictUI.list_rules()
    assert rule.name == "duration"
    assert rule.event.type == "overtime"
    assert length(rule.conditions["all"]) == 1
    assert hd(rule.conditions["all"])["fact"] == "gameDuration"
    assert hd(rule.conditions["all"])["value"] == 40
  end

  test "shows an error and persists nothing when a leaf fact is empty", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/rules/new")

    view |> element("button", "+ condition") |> render_click()

    view
    |> form("#rule-form", %{rule: %{name: "bad", priority: 1, event_type: "x"}})
    |> render_submit()

    assert has_element?(view, "#save-errors")
    assert VerdictUI.list_rules() == []
  end

  test "edit form loads an existing rule and its conditions", %{conn: conn} do
    {:ok, rule} = VerdictUI.create_rule(@attrs)
    {:ok, view, _} = live(conn, ~p"/rules/#{rule.id}/edit")
    assert render(view) =~ "Edit rule"
    assert has_element?(view, ~s(input[name="rule[name]"][value="fouled-out"]))
    assert has_element?(view, ~s(input[name="cond-0-fact"][value="gameDuration"]))
    assert has_element?(view, ~s(input[name="cond-1-fact"][value="personalFoulCount"]))
  end

  test "saves event params", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/rules/new")

    view |> render_click("add-param")
    assert has_element?(view, "input[name=param-0-name]")

    view |> render_change("param", %{"_target" => ["param-0-name"], "param-0-name" => "message"})

    view
    |> render_change("param", %{"_target" => ["param-0-value"], "param-0-value" => "Overtime!"})

    view
    |> form("#rule-form", %{rule: %{name: "ot", priority: 1, event_type: "overtime"}})
    |> render_submit()

    [rule] = VerdictUI.list_rules()
    assert rule.event.type == "overtime"
    assert rule.event.params == %{"message" => "Overtime!"}
  end

  test "saves an eex_string template param", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/rules/new")

    view |> render_click("add-param")
    view |> render_change("param", %{"_target" => ["param-0-name"], "param-0-name" => "msg"})

    view
    |> render_change("param", %{"_target" => ["param-0-value"], "param-0-value" => "hi <%= x %>"})

    view
    |> render_change("param", %{"_target" => ["param-0-template"], "param-0-template" => "true"})

    view
    |> form("#rule-form", %{rule: %{name: "t", priority: 1, event_type: "e"}})
    |> render_submit()

    [rule] = VerdictUI.list_rules()
    assert rule.event.params == %{"msg" => %{"eex_string" => "hi <%= x %>"}}
  end

  test "edit form loads a template param with the toggle checked", %{conn: conn} do
    {:ok, rule} =
      VerdictUI.create_rule(%{
        name: "tpl",
        event: %{"type" => "e", "params" => %{"msg" => %{"eex_string" => "hi <%= x %>"}}},
        conditions: %{"all" => [%{"fact" => "x", "operator" => "equal", "value" => 1}]}
      })

    {:ok, view, _} = live(conn, ~p"/rules/#{rule.id}/edit")
    assert has_element?(view, "input[name=param-0-template][checked]")
    assert has_element?(view, ~s(select[name="param-0-type"] option[value="string"][selected]))
    assert render(view) =~ "hi &lt;%= x %&gt;"
  end

  test "saves a typed eex_integer template param", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/rules/new")

    view |> render_click("add-param")
    view |> render_change("param", %{"_target" => ["param-0-name"], "param-0-name" => "count"})

    view
    |> render_change("param", %{"_target" => ["param-0-value"], "param-0-value" => "<%= count %>"})

    view
    |> render_change("param", %{"_target" => ["param-0-template"], "param-0-template" => "true"})

    view |> render_change("param", %{"_target" => ["param-0-type"], "param-0-type" => "integer"})

    view
    |> form("#rule-form", %{rule: %{name: "t", priority: 1, event_type: "e"}})
    |> render_submit()

    [rule] = VerdictUI.list_rules()
    assert rule.event.params == %{"count" => %{"eex_integer" => "<%= count %>"}}
  end

  test "edit form loads a typed marker with the select set", %{conn: conn} do
    {:ok, rule} =
      VerdictUI.create_rule(%{
        name: "n",
        event: %{"type" => "e", "params" => %{"count" => %{"eex_integer" => "<%= count %>"}}},
        conditions: %{"all" => [%{"fact" => "count", "operator" => "equal", "value" => 1}]}
      })

    {:ok, view, _} = live(conn, ~p"/rules/#{rule.id}/edit")
    assert has_element?(view, "input[name=param-0-template][checked]")
    assert has_element?(view, ~s(select[name="param-0-type"] option[value="integer"][selected]))
  end

  test "edit: saves a changed event type and event param", %{conn: conn} do
    {:ok, rule} =
      VerdictUI.create_rule(%{
        name: "u",
        event: %{"type" => "verdict", "params" => %{"msg" => "small"}},
        conditions: %{"all" => [%{"fact" => "fouls", "operator" => "greaterThan", "value" => 5}]}
      })

    {:ok, view, _} = live(conn, ~p"/rules/#{rule.id}/edit")
    view |> render_change("param", %{"_target" => ["param-0-value"], "param-0-value" => "big"})

    view
    |> form("#rule-form", %{rule: %{name: "u", priority: 1, event_type: "fouledOut"}})
    |> render_submit()

    updated = VerdictUI.get_rule(rule.id)
    assert updated.event.type == "fouledOut"
    assert updated.event.params == %{"msg" => "big"}
  end

  test "edit: adding a new event param persists it", %{conn: conn} do
    {:ok, rule} =
      VerdictUI.create_rule(%{
        name: "u",
        event: %{"type" => "verdict", "params" => %{"msg" => "small"}},
        conditions: %{"all" => [%{"fact" => "fouls", "operator" => "greaterThan", "value" => 5}]}
      })

    {:ok, view, _} = live(conn, ~p"/rules/#{rule.id}/edit")
    view |> render_click("add-param")
    view |> render_change("param", %{"_target" => ["param-1-name"], "param-1-name" => "count"})
    view |> render_change("param", %{"_target" => ["param-1-value"], "param-1-value" => "3"})

    view
    |> form("#rule-form", %{rule: %{name: "u", priority: 1, event_type: "verdict"}})
    |> render_submit()

    updated = VerdictUI.get_rule(rule.id)
    assert updated.event.params == %{"msg" => "small", "count" => 3}
  end

  test "creates a rule with a distinct failure event", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/rules/new")

    view |> element("button", "+ condition") |> render_click()
    view |> element("input[name=cond-0-fact]") |> render_change(%{"cond-0-fact" => "fouls"})
    view |> element("input[name=cond-0-value]") |> render_change(%{"cond-0-value" => "5"})

    view |> render_click("add-fparam")

    view
    |> render_change("fparam", %{"_target" => ["fparam-0-name"], "fparam-0-name" => "reason"})

    view
    |> render_change("fparam", %{
      "_target" => ["fparam-0-value"],
      "fparam-0-value" => "not fouled"
    })

    view
    |> form("#rule-form", %{
      rule: %{
        name: "foul",
        priority: 1,
        event_type: "fouledOut",
        failure_event_type: "notifyFoul"
      }
    })
    |> render_submit()

    [rule] = VerdictUI.list_rules()
    assert rule.event.type == "fouledOut"
    assert rule.failure_event.type == "notifyFoul"
    assert rule.failure_event.params == %{"reason" => "not fouled"}
  end

  test "blocks saving an ill-formed eex template", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/rules/new")

    view |> render_click("add-param")
    view |> render_change("param", %{"_target" => ["param-0-name"], "param-0-name" => "msg"})

    view
    |> render_change("param", %{"_target" => ["param-0-value"], "param-0-value" => "<%= broken"})

    view
    |> render_change("param", %{"_target" => ["param-0-template"], "param-0-template" => "true"})

    view
    |> form("#rule-form", %{rule: %{name: "t", priority: 1, event_type: "e"}})
    |> render_submit()

    assert has_element?(view, "#template-errors")
    assert VerdictUI.list_rules() == []
  end
end
