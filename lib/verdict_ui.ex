defmodule VerdictUI do
  @moduledoc """
  Context for Verdict rules persisted in the database.

  This is the embeddable surface: it works over `VerdictUI.Rule` and talks to
  whichever Ecto repo is configured under `config :verdict_ui, :repo` (defaulting
  to `VerdictUI.Repo`). A host app points `:repo` at its own repo to store rules
  in its own database.
  """
  import Ecto.Query
  alias Verdict.{Engine, RunResult}
  alias VerdictUI.{Rule, Scenario}

  @doc "The repo this context uses (configurable for embedding)."
  def repo, do: Application.get_env(:verdict_ui, :repo, VerdictUI.Repo)

  @doc "Lists all rules, highest priority first (ties broken by name)."
  def list_rules do
    query = from(r in Rule, order_by: [desc: r.priority, asc: r.name])
    repo().all(query)
  end

  @doc "Fetches a rule by id, or `nil`."
  def get_rule(id), do: repo().get(Rule, id)

  @doc "An empty changeset for building a new rule."
  def change_new_rule, do: change_rule(%Rule{})

  @doc "A changeset for editing `rule`."
  def change_rule(%Rule{} = rule), do: Rule.changeset(rule, %{})

  @doc "Creates a rule from `attrs`. Returns `{:ok, rule}` or `{:error, changeset}`."
  def create_rule(attrs) do
    %Rule{}
    |> Rule.changeset(attrs)
    |> repo().insert()
  end

  @doc "Updates `rule` from `attrs`. Returns `{:ok, rule}` or `{:error, changeset}`."
  def update_rule(%Rule{} = rule, attrs) do
    rule
    |> Rule.changeset(attrs)
    |> repo().update()
  end

  @doc "Deletes `rule`. Returns `{:ok, rule}` or `{:error, changeset}`."
  def delete_rule(%Rule{} = rule), do: repo().delete(rule)

  # --- scenarios -------------------------------------------------------------

  @doc "Lists all scenarios."
  def list_scenarios, do: repo().all(Scenario)

  @doc "Fetches a scenario by id, or `nil`."
  def get_scenario(id), do: repo().get(Scenario, id)

  @doc "An empty changeset for a new scenario."
  def change_new_scenario, do: change_scenario(%Scenario{})

  @doc "A changeset for editing `scenario`."
  def change_scenario(%Scenario{} = scenario), do: Scenario.changeset(scenario, %{})

  @doc "Creates a scenario. Returns `{:ok, scenario}` or `{:error, changeset}`."
  def create_scenario(attrs) do
    %Scenario{} |> Scenario.changeset(attrs) |> repo().insert()
  end

  @doc "Updates `scenario`. Returns `{:ok, scenario}` or `{:error, changeset}`."
  def update_scenario(%Scenario{} = scenario, attrs) do
    scenario |> Scenario.changeset(attrs) |> repo().update()
  end

  @doc "Deletes `scenario`. Returns `{:ok, scenario}` or `{:error, changeset}`."
  def delete_scenario(%Scenario{} = scenario), do: repo().delete(scenario)

  @doc """
  The rules associated with `scenario`, in evaluation order (priority desc).
  Rule ids that no longer exist are dropped.
  """
  def scenario_rules(%Scenario{} = scenario) do
    query =
      from(r in Rule,
        where: r.id in ^scenario.rule_ids,
        order_by: [desc: r.priority, asc: r.name]
      )

    repo().all(query)
  end

  @doc """
  Evaluates a saved scenario against the engine: runs every associated rule
  together with the scenario's facts. Returns `{:ok, result_map}` (the
  `Verdict.RunResult.to_map/1` shape) or `{:error, message}`.
  """
  def run_scenario(%Scenario{} = scenario) do
    opts = run_opts(scenario.allow_unsafe, scenario.allow_undefined_facts)
    run_rules(scenario_rules(scenario), scenario.facts, opts)
  end

  @doc """
  Builds the engine keyword options from the two boolean run toggles: an
  `:allow_unsafe_eex` entry when `allow_unsafe` is on and an
  `:allow_undefined_facts` entry when `allow_undefined_facts` is on.
  """
  def run_opts(allow_unsafe, allow_undefined_facts) do
    unsafe = if allow_unsafe, do: [allow_unsafe_eex: true], else: []
    undefined = if allow_undefined_facts, do: [allow_undefined_facts: true], else: []
    unsafe ++ undefined
  end

  @doc """
  Runs `rules` together against the engine with `facts` (a `name => value` map).

  `opts` are forwarded to `Verdict.Engine.new/1` (e.g. `:allow_unsafe_eex`,
  `:allow_undefined_facts`); options omitted fall back to the engine defaults.
  Returns `{:ok, result_map}` or `{:error, message}`.
  """
  def run_rules(rules, facts, opts \\ []) when is_list(rules) and is_map(facts) do
    try do
      engine =
        Enum.reduce(rules, Engine.new(opts), fn rule, eng ->
          {:ok, eng, _} = Engine.add_rule(eng, Rule.to_engine_attrs(rule))
          eng
        end)

      {:ok, RunResult.to_map(Engine.run(engine, facts))}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end
end
