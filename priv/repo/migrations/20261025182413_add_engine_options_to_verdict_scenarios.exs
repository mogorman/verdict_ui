defmodule VerdictUI.Repo.Migrations.AddEngineOptionsToVerdictScenarios do
  use Ecto.Migration

  def change do
    alter table(:verdict_scenarios) do
      add :allow_undefined_conditions, :boolean, default: false, null: false
      add :strict, :boolean, default: false, null: false
      add :replace_facts_in_event_params, :boolean, default: false, null: false
      add :report, :string, default: "full", null: false
      add :schedule, :string, default: "serial", null: false
      add :parallel_concurrency, :integer
      add :log_level, :string
    end
  end
end
