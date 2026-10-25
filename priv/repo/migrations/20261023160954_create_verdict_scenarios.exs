defmodule VerdictUI.Repo.Migrations.CreateVerdictScenarios do
  use Ecto.Migration

  def change do
    create table("verdict_scenarios", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :facts, :map, null: false, default: %{}
      add :rule_ids, {:array, :uuid}, null: false, default: []
      timestamps()
    end
  end
end
