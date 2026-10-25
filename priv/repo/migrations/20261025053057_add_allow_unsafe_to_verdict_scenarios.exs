defmodule VerdictUI.Repo.Migrations.AddAllowUnsafeToVerdictScenarios do
  use Ecto.Migration

  def change do
    alter table(:verdict_scenarios) do
      add :allow_unsafe, :boolean, default: false, null: false
    end
  end
end
