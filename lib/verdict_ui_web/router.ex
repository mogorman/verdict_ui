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

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:verdict_ui, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: VerdictUIWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
