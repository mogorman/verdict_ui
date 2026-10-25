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

  # Explicit string -> atom maps for the enum-ish engine options, so we never
  # call String.to_atom/1 on form input.
  @report_values %{
    "full" => :full,
    "result_only" => :result_only,
    "failures_only" => :failures_only
  }
  @schedule_values %{"serial" => :serial, "parallel" => :parallel}
  @log_values %{"debug" => :debug, "info" => :info, "warning" => :warning, "error" => :error}

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
    run_rules(scenario_rules(scenario), scenario.facts, run_opts(scenario_to_opts(scenario)))
  end

  @doc """
  Builds the engine keyword options from a map of run-option values.

  Only non-default values are emitted, so omitted options fall back to the
  engine defaults (and `:allow_unsafe_eex` to the application config). Accepts a
  map keyed by: `allow_unsafe`, `allow_undefined_facts`,
  `allow_undefined_conditions`, `strict`, `replace_facts_in_event_params`,
  `report`, `schedule`, `parallel_concurrency`, `log_level`.
  """
  def run_opts(opts) do
    opts = Map.new(opts)
    report = report_atom(opts[:report])
    schedule = schedule_atom(opts[:schedule])
    log = log_atom(opts[:log_level])
    pc = opts[:parallel_concurrency]

    [
      if(opts[:allow_unsafe], do: [allow_unsafe_eex: true], else: []),
      if(opts[:allow_undefined_facts], do: [allow_undefined_facts: true], else: []),
      if(opts[:allow_undefined_conditions], do: [allow_undefined_conditions: true], else: []),
      if(opts[:strict], do: [strict: true], else: []),
      if(opts[:replace_facts_in_event_params],
        do: [replace_facts_in_event_params: true],
        else: []
      ),
      if(report != :full, do: [report: report], else: []),
      if(schedule != :serial, do: [schedule: schedule], else: []),
      if(pc, do: [parallel_concurrency: pc], else: []),
      if(log, do: [log: log], else: [])
    ]
    |> List.flatten()
  end

  @doc """
  Runs `rules` together against the engine with `facts` (a `name => value` map).

  `opts` are forwarded to both `Verdict.Engine.new/1` and `Verdict.Engine.run/3`
  (the latter so run-time options like `:schedule` and `:parallel_concurrency`
  take effect); options omitted fall back to the engine defaults.
  Returns `{:ok, result_map}` or `{:error, message}`.
  """
  def run_rules(rules, facts, opts \\ []) when is_list(rules) and is_map(facts) do
    try do
      engine =
        Enum.reduce(rules, Engine.new(opts), fn rule, eng ->
          {:ok, eng, _} = Engine.add_rule(eng, Rule.to_engine_attrs(rule))
          eng
        end)

      {:ok, RunResult.to_map(Engine.run(engine, facts, opts))}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  # Maps a saved scenario's option fields to the `run_opts/1` value map.
  defp scenario_to_opts(%Scenario{} = s) do
    %{
      allow_unsafe: s.allow_unsafe,
      allow_undefined_facts: s.allow_undefined_facts,
      allow_undefined_conditions: s.allow_undefined_conditions,
      strict: s.strict,
      replace_facts_in_event_params: s.replace_facts_in_event_params,
      report: s.report,
      schedule: s.schedule,
      parallel_concurrency: s.parallel_concurrency,
      log_level: s.log_level
    }
  end

  defp report_atom(nil), do: :full
  defp report_atom(v), do: Map.get(@report_values, v, :full)

  defp schedule_atom(nil), do: :serial
  defp schedule_atom(v), do: Map.get(@schedule_values, v, :serial)

  defp log_atom(nil), do: nil
  defp log_atom(v), do: Map.get(@log_values, v)
end
