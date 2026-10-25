defmodule VerdictUI.Repo.Migrations.CreateVerdictRules do
  use Ecto.Migration

  def change do
    create table("verdict_rules", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string
      add :priority, :integer, default: 1, null: false
      add :extra, :map, default: %{}
      add :event, :map, null: false
      add :conditions, :map, null: false
      timestamps()
    end
  end
end
