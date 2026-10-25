defmodule VerdictUIWeb.ScenarioIndexLiveTest do
  @moduledoc false
  use VerdictUIWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias VerdictUI

  test "lists and deletes scenarios", %{conn: conn} do
    {:ok, scenario} = VerdictUI.create_scenario(%{name: "reg"})
    {:ok, view, html} = live(conn, ~p"/scenarios")
    assert html =~ "reg"

    render_click(view, "delete", %{"value" => scenario.id})
    refute VerdictUI.get_scenario(scenario.id)
  end

  test "shows empty state", %{conn: conn} do
    for s <- VerdictUI.list_scenarios(), do: VerdictUI.delete_scenario(s)
    {:ok, _view, html} = live(conn, ~p"/scenarios")
    assert html =~ "No scenarios yet"
  end
end
