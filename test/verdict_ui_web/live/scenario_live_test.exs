defmodule VerdictUIWeb.ScenarioLiveTest do
  @moduledoc false
  use VerdictUIWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias VerdictUI

  @rule_a %{
    name: "ra",
    priority: 2,
    event: %{"type" => "e"},
    conditions: %{"all" => [%{"fact" => "x", "operator" => "equal", "value" => 1}]}
  }

  @rule_b %{
    name: "rb",
    priority: 1,
    event: %{"type" => "e"},
    conditions: %{"all" => [%{"fact" => "x", "operator" => "greaterThan", "value" => 5}]}
  }

  test "selects rules, adds a fact, runs, and saves the scenario", %{conn: conn} do
    {:ok, a} = VerdictUI.create_rule(@rule_a)
    {:ok, b} = VerdictUI.create_rule(@rule_b)
    {:ok, view, _} = live(conn, ~p"/scenarios/new")

    view |> element("#scenario-name") |> render_change(%{"scenario[name]" => "reg"})

    view |> render_change("toggle-rule", %{"_target" => ["rule-#{a.id}"], "rule-#{a.id}" => a.id})
    view |> render_change("toggle-rule", %{"_target" => ["rule-#{b.id}"], "rule-#{b.id}" => b.id})

    view |> render_click("add-fact")
    view |> render_change("fact", %{"_target" => ["fact-0-name"], "fact-0-name" => "x"})
    view |> render_change("fact", %{"_target" => ["fact-0-value"], "fact-0-value" => "10"})

    render_click(view, "run")
    # rb: x > 5
    assert has_element?(view, "#run-result .badge-success")
    # ra: x == 1
    assert has_element?(view, "#run-result .badge-error")
    # only the fired rule shows its event; the not-fired rule shows none
    assert render(view) =~ ">event<"
    refute render(view) =~ ">failure event<"

    render_click(view, "save")
    scenario = Enum.find(VerdictUI.list_scenarios(), &(&1.name == "reg"))
    assert scenario != nil
    assert MapSet.equal?(MapSet.new(scenario.rule_ids), MapSet.new([a.id, b.id]))
    assert scenario.facts == %{"x" => 10}
  end

  test "saves engine options chosen in the form", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/scenarios/new")

    view |> element("#scenario-name") |> render_change(%{"scenario[name]" => "opts"})

    view |> element("#scenario-strict") |> render_change(%{"strict" => "1"})
    view |> element("#scenario-report") |> render_change(%{"report" => "failures_only"})

    view
    |> element("#scenario-schedule")
    |> render_change(%{"schedule" => "parallel"})

    view
    |> element("#scenario-parallel-concurrency")
    |> render_change(%{"parallel_concurrency" => "4"})

    view |> element("#scenario-log-level") |> render_change(%{"log_level" => "debug"})

    render_click(view, "save")

    scenario = Enum.find(VerdictUI.list_scenarios(), &(&1.name == "opts"))
    assert scenario.strict == true
    assert scenario.report == "failures_only"
    assert scenario.schedule == "parallel"
    assert scenario.parallel_concurrency == 4
    assert scenario.log_level == "debug"
  end

  test "shows a failed rule's failure event (not its success event) in the results", %{conn: conn} do
    {:ok, rule} =
      VerdictUI.create_rule(%{
        name: "fr",
        event: %{"type" => "success-e"},
        failure_event: %{"type" => "fail-e"},
        conditions: %{"all" => [%{"fact" => "x", "operator" => "equal", "value" => 1}]}
      })

    {:ok, view, _} = live(conn, ~p"/scenarios/new")
    view |> element("#scenario-name") |> render_change(%{"scenario[name]" => "fs"})

    view
    |> render_change("toggle-rule", %{
      "_target" => ["rule-#{rule.id}"],
      "rule-#{rule.id}" => rule.id
    })

    view |> render_click("add-fact")
    view |> render_change("fact", %{"_target" => ["fact-0-name"], "fact-0-name" => "x"})
    view |> render_change("fact", %{"_target" => ["fact-0-value"], "fact-0-value" => "9"})

    render_click(view, "run")

    # x=9 != 1 so the rule does not fire: its failure event is shown, not the success event
    assert render(view) =~ ">failure event<"
    assert has_element?(view, "#results", "fail-e")
    refute has_element?(view, "#results", "success-e")
    assert has_element?(view, "#run-raw-json")
  end

  test "allow_undefined_facts runs a rule that references an unprovided fact", %{conn: conn} do
    {:ok, rule} =
      VerdictUI.create_rule(%{
        name: "udef",
        event: %{"type" => "e"},
        conditions: %{"all" => [%{"fact" => "missing", "operator" => "equal", "value" => 1}]}
      })

    {:ok, view, _} = live(conn, ~p"/scenarios/new")
    view |> element("#scenario-name") |> render_change(%{"scenario[name]" => "ud"})

    view
    |> render_change("toggle-rule", %{
      "_target" => ["rule-#{rule.id}"],
      "rule-#{rule.id}" => rule.id
    })

    view |> render_change("allow-undefined-facts", %{"allow_undefined_facts" => "true"})
    render_click(view, "run")

    # "missing" is not provided; with the toggle on it evaluates as nil instead of erroring
    assert has_element?(view, "#run-result")
  end

  test "saves allow_undefined_facts on a new scenario", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/scenarios/new")
    view |> element("#scenario-name") |> render_change(%{"scenario[name]" => "save-ud"})
    view |> render_change("allow-undefined-facts", %{"allow_undefined_facts" => "true"})
    render_click(view, "save")

    scenario = Enum.find(VerdictUI.list_scenarios(), &(&1.name == "save-ud"))
    assert scenario.allow_undefined_facts == true
  end

  test "saves allow_undefined_facts when toggled in edit mode", %{conn: conn} do
    {:ok, scenario} = VerdictUI.create_scenario(%{name: "edit-ud"})
    refute scenario.allow_undefined_facts

    {:ok, view, _} = live(conn, ~p"/scenarios/#{scenario.id}")
    view |> render_change("allow-undefined-facts", %{"allow_undefined_facts" => "true"})
    render_click(view, "save")

    assert VerdictUI.get_scenario(scenario.id).allow_undefined_facts == true
  end

  test "loads a saved scenario and re-runs it", %{conn: conn} do
    {:ok, a} = VerdictUI.create_rule(@rule_a)

    {:ok, scenario} =
      VerdictUI.create_scenario(%{name: "reg", facts: %{"x" => 1}, rule_ids: [a.id]})

    {:ok, view, html} = live(conn, ~p"/scenarios/#{scenario.id}")
    assert html =~ "reg"
    # the saved fact row is loaded
    assert has_element?(view, "input[name=fact-0-name][value=x]")

    render_click(view, "run")
    # x == 1 fires ra
    assert has_element?(view, "#run-result .badge-success")
  end

  test "shows rendered event params in the result", %{conn: conn} do
    {:ok, a} =
      VerdictUI.create_rule(%{
        name: "tmpl",
        event: %{"type" => "hi", "params" => %{"msg" => %{"eex_string" => "Hey <%= who %>!"}}},
        conditions: %{"all" => [%{"fact" => "who", "operator" => "notEqual", "value" => ""}]}
      })

    {:ok, view, _} = live(conn, ~p"/scenarios/new")
    view |> render_change("toggle-rule", %{"_target" => ["rule-#{a.id}"], "rule-#{a.id}" => a.id})
    view |> render_click("add-fact")
    view |> render_change("fact", %{"_target" => ["fact-0-name"], "fact-0-name" => "who"})
    view |> render_change("fact", %{"_target" => ["fact-0-value"], "fact-0-value" => "Sam"})
    render_click(view, "run")

    assert render(view) =~ "Hey Sam!"
  end

  test "allow-unsafe toggle enables control-flow event templates", %{conn: conn} do
    {:ok, a} =
      VerdictUI.create_rule(%{
        name: "u",
        event: %{
          "type" => "verdict",
          "params" => %{
            "msg" => %{"eex_string" => "<% if x > 5 do %>big<% else %>small<% end %>"}
          }
        },
        conditions: %{"all" => [%{"fact" => "x", "operator" => "greaterThan", "value" => 0}]}
      })

    {:ok, view, _} = live(conn, ~p"/scenarios/new")
    view |> render_change("toggle-rule", %{"_target" => ["rule-#{a.id}"], "rule-#{a.id}" => a.id})
    view |> render_click("add-fact")
    view |> render_change("fact", %{"_target" => ["fact-0-name"], "fact-0-name" => "x"})
    view |> render_change("fact", %{"_target" => ["fact-0-value"], "fact-0-value" => "10"})

    # the control is present, and without it the control-flow template is blocked
    assert has_element?(view, "#allow-unsafe")
    render_click(view, "run")
    assert has_element?(view, "#run-error")

    # with the toggle, the same rule runs and renders the template
    view
    |> render_change("allow-unsafe", %{"_target" => ["allow_unsafe"], "allow_unsafe" => "true"})

    render_click(view, "run")
    assert has_element?(view, "#run-result")
    assert render(view) =~ "big"
  end
end
