defmodule VerdictUIWeb.RuleTestLiveTest do
  @moduledoc false
  use VerdictUIWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias VerdictUI

  test "runs a rule against runtime facts", %{conn: conn} do
    {:ok, rule} =
      VerdictUI.create_rule(%{
        name: "duration-rule",
        event: %{"type" => "timeUp"},
        conditions: %{
          "all" => [%{"fact" => "gameDuration", "operator" => "equal", "value" => 40}]
        }
      })

    {:ok, view, html} = live(conn, ~p"/rules/#{rule.id}/test")
    assert html =~ "gameDuration"

    view |> render_change("fact", %{"fact-0-value" => "40"})
    render_click(view, "run")
    assert has_element?(view, "#run-result .badge-success")

    view |> render_change("fact", %{"fact-0-value" => "50"})
    render_click(view, "run")
    assert has_element?(view, "#run-result .badge-error")
  end

  test "reports an undefined fact as an error", %{conn: conn} do
    {:ok, rule} =
      VerdictUI.create_rule(%{
        name: "no-fact-rule",
        event: %{"type" => "x"},
        conditions: %{"all" => [%{"fact" => "missing", "operator" => "equal", "value" => 1}]}
      })

    {:ok, view, _} = live(conn, ~p"/rules/#{rule.id}/test")
    render_click(view, "remove-fact", %{"value" => "0"})
    render_click(view, "run")
    assert has_element?(view, "#run-error")
  end

  test "shows the emitted event with rendered template params", %{conn: conn} do
    {:ok, rule} =
      VerdictUI.create_rule(%{
        name: "foul-msg",
        event: %{
          "type" => "fouledOut",
          "params" => %{"msg" => %{"eex_string" => "Fouls: <%= fouls %>!"}}
        },
        conditions: %{
          "all" => [%{"fact" => "fouls", "operator" => "greaterThanInclusive", "value" => 5}]
        }
      })

    {:ok, view, _} = live(conn, ~p"/rules/#{rule.id}/test")
    view |> render_change("fact", %{"fact-0-value" => "6"})
    render_click(view, "run")

    assert has_element?(view, "#run-result .badge-success")
    assert render(view) =~ "fouledOut"
    assert render(view) =~ "Fouls: 6!"
  end

  test "unsafe eex templates require the toggle", %{conn: conn} do
    {:ok, rule} =
      VerdictUI.create_rule(%{
        name: "unsafe-msg",
        event: %{
          "type" => "t",
          "params" => %{
            "msg" => %{"eex_string" => "<%= inspect(\"big\") %>"}
          }
        },
        conditions: %{
          "all" => [%{"fact" => "fouls", "operator" => "greaterThanInclusive", "value" => 1}]
        }
      })

    {:ok, view, _} = live(conn, ~p"/rules/#{rule.id}/test")
    view |> render_change("fact", %{"fact-0-value" => "6"})

    # a non-whitelisted call needs the toggle; without it the run errors
    render_click(view, "run")
    assert has_element?(view, "#run-error")
    refute has_element?(view, "#run-result")

    # enabling it lets the run succeed
    view |> render_change("allow-unsafe", %{"allow_unsafe" => "true"})
    render_click(view, "run")
    assert has_element?(view, "#run-result")
    refute has_element?(view, "#run-error")
  end
end
