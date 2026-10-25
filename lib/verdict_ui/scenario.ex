defmodule VerdictUI.Scenario do
  @moduledoc """
  A saved, reusable test case: a named set of rules plus the runtime facts to run
  them with. Run the scenario (see `VerdictUI.run_scenario/1`) to evaluate every
  associated rule together against the engine.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "verdict_scenarios" do
    field(:name, :string)
    field(:facts, :map, default: %{})
    field(:rule_ids, {:array, :binary_id}, default: [])
    field(:allow_unsafe, :boolean, default: false)
    timestamps()
  end

  @doc "An insert or update changeset. Only `name` is required."
  def changeset(%__MODULE__{} = scenario, attrs) do
    scenario
    |> cast(attrs, [:name, :facts, :rule_ids, :allow_unsafe])
    |> validate_required([:name])
  end
end
