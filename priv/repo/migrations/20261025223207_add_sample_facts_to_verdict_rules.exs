defmodule VerdictUI.Repo.Migrations.AddSampleFactsToVerdictRules do
  use Ecto.Migration

  def change do
    alter table("verdict_rules") do
      add :sample_facts, :map, default: %{}, null: false
    end
  end
end
