defmodule VerdictUI.Repo.Migrations.AddFailureEventToVerdictRules do
  use Ecto.Migration

  def change do
    alter table(:verdict_rules) do
      add :failure_event, :map
    end
  end
end
