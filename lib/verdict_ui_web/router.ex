defmodule VerdictUIWeb.Router do
  use VerdictUIWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {VerdictUIWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", VerdictUIWeb do
    pipe_through :browser

    live "/", RuleIndexLive

    live_session :rules do
      live "/rules", RuleIndexLive
      live "/rules/new", RuleFormLive, :new
      live "/rules/:id/edit", RuleFormLive, :edit
      live "/rules/:id/test", RuleTestLive
    end

    live_session :scenarios do
      live "/scenarios", ScenarioIndexLive
      live "/scenarios/new", ScenarioLive
      live "/scenarios/:id", ScenarioLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", VerdictUIWeb do
  #   pipe_through :api
  # end
end
