defmodule VerdictUI.Repo.Migrations.AddAllowUndefinedFactsToVerdictScenarios do
  use Ecto.Migration

  def change do
    alter table(:verdict_scenarios) do
      add :allow_undefined_facts, :boolean, default: false, null: false
    end
  end
end
