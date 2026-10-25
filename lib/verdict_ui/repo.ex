defmodule VerdictUI.Repo do
  use Ecto.Repo,
    otp_app: :verdict_ui,
    adapter: Ecto.Adapters.Postgres
end
