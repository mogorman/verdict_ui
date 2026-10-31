defmodule VerdictUI.Rule do
  @moduledoc """
  The persisted form of a `Verdict.Rule`, stored in the `verdict_rules` table.

  It lives in its own table so a host application can mount `VerdictUI` without
  colliding with any `rules` table of its own. The schema reuses the engine's
  `Verdict.Event` and `Verdict.Types.Condition` types, and `changeset/2` delegates
  all validation to `Verdict.Rule.changeset/2` — the single source of truth for
  what a rule is — then re-homes the result onto this schema.

  `to_engine_attrs/1` turns a stored rule back into the string-keyed map that
  `Verdict.Engine.add_rule/2` consumes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Verdict.{Condition, Event, Rule, Types}

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "verdict_rules" do
    field(:name, :string)
    field(:priority, :integer, default: 1)
    field(:extra, :map, default: %{})
    embeds_one(:event, Event)
    embeds_one(:failure_event, Event)
    field(:conditions, Types.Condition)
    field(:sample_facts, :map, default: %{})
    timestamps()
  end

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          priority: integer(),
          extra: map(),
          event: Event.t() | nil,
          failure_event: Event.t() | nil,
          conditions: Condition.t() | map(),
          sample_facts: map(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  @doc """
  Builds an insert or update changeset for a `t:VerdictUI.Rule/0`.

  Validation is delegated to `Verdict.Rule.changeset/2`; the (already validated)
  changes are re-applied onto this schema and any errors re-attached. Returns a
  valid changeset on success, or an invalid one carrying the same errors.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = rule, attrs) do
    source = Rule.changeset(to_source(rule), attrs)
    base = rehome(rule, source.changes)
    if source.valid?, do: base, else: merge_errors(base, source.errors)
  end

  # Maps this rule onto a `Verdict.Rule` so `Verdict.Rule.changeset/2` validates
  # against the full current state. Carrying the existing `event` / `conditions`
  # means an update that omits them keeps them instead of failing as blank.
  defp to_source(%__MODULE__{} = rule) do
    %Rule{
      id: rule.id,
      name: rule.name,
      priority: rule.priority,
      extra: rule.extra,
      event: rule.event,
      failure_event: rule.failure_event,
      conditions: rule.conditions,
      sample_facts: rule.sample_facts
    }
  end

  # Re-applies `changes` (produced against `Verdict.Rule`) onto `rule`. The two
  # schemas share field names and the `event` / `conditions` types, so each value
  # applies as-is. `put_change/2` trusts the value, so no field list is needed.
  defp rehome(rule, changes) do
    Enum.reduce(changes, change(rule), fn {field, value}, acc ->
      put_change(acc, field, value)
    end)
  end

  # Re-attaches `source.errors` onto `acc`. The message templates render against
  # this schema's identically named fields, so they are reused verbatim.
  defp merge_errors(acc, []), do: acc

  defp merge_errors(acc, errors) do
    Enum.reduce(errors, acc, fn {field, {message, opts}}, acc ->
      add_error(acc, field, message, opts)
    end)
  end

  @doc """
  Converts a stored rule to the string-keyed map `Verdict.Engine.add_rule/2`
  accepts. The condition tree is emitted as its JSON form whether it is still a
  `t:Verdict.Condition/0` (freshly written) or a decoded map (loaded from the
  database).
  """
  @spec to_engine_attrs(t()) :: map()
  def to_engine_attrs(%__MODULE__{
        name: name,
        priority: priority,
        extra: extra,
        event: %Event{} = event,
        failure_event: failure_event,
        conditions: conditions
      }) do
    %{
      "name" => name,
      "priority" => priority,
      "extra" => extra,
      "event" => Event.to_map(event),
      "failure_event" => failure_event && Event.to_map(failure_event),
      "conditions" => conditions_map(conditions)
    }
  end

  defp conditions_map(%Condition{} = condition), do: Types.Condition.to_map(condition)
  defp conditions_map(map) when is_map(map), do: map

  @doc """
  The rule as a JSON-compatible map — the inverse of `changeset/2`, so encoding
  this to JSON and feeding it back through `VerdictUI.create_rule/1` round-trips
  unchanged. `id`/timestamps are omitted; default/empty fields (`priority` 1,
  empty `extra`, absent `sample_facts`) are left out, mirroring
  `Verdict.Rule.to_map/1`.
  """
  @spec to_json_map(t()) :: map()
  def to_json_map(%__MODULE__{} = rule) do
    %{
      "name" => rule.name,
      "conditions" => conditions_map(rule.conditions)
    }
    |> omit_nil("event", rule.event && Event.to_map(rule.event))
    |> omit_nil("failure_event", rule.failure_event && Event.to_map(rule.failure_event))
    |> omit_nil("priority", if(rule.priority in [nil, 1], do: nil, else: rule.priority))
    |> omit_nil("extra", if(rule.extra in [nil, %{}], do: nil, else: rule.extra))
    |> omit_nil(
      "sample_facts",
      if(rule.sample_facts in [nil, %{}], do: nil, else: rule.sample_facts)
    )
  end

  @doc "A `data:` URI `href` that downloads the rule as JSON."
  @spec export_href(t()) :: String.t()
  def export_href(%__MODULE__{} = rule) do
    "data:application/json;base64," <> Base.encode64(VerdictUI.JSON.encode!(to_json_map(rule)))
  end

  defp omit_nil(map, _key, nil), do: map
  defp omit_nil(map, key, value), do: Map.put(map, key, value)
end
