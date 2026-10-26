defmodule VerdictUITest do
  use VerdictUI.DataCase, async: false

  alias VerdictUI
  alias VerdictUI.Rule

  @rule_attrs %{
    name: "fouled-out",
    priority: 5,
    event: %{"type" => "fouledOut", "params" => %{"message" => "Player has fouled out!"}},
    conditions: %{
      "all" => [
        %{"fact" => "gameDuration", "operator" => "equal", "value" => 40},
        %{"fact" => "personalFoulCount", "operator" => "greaterThanInclusive", "value" => 5}
      ]
    }
  }

  test "create_rule/1 with valid data" do
    {:ok, rule} = VerdictUI.create_rule(@rule_attrs)
    assert rule.name == "fouled-out"
    assert rule.priority == 5
    assert rule.event.type == "fouledOut"
    assert rule.event.params == %{"message" => "Player has fouled out!"}
    assert is_binary(rule.id)
    assert rule.conditions != nil
  end

  test "create_rule/1 without an id assigns one" do
    {:ok, rule} = VerdictUI.create_rule(@rule_attrs)
    id = rule.id
    assert is_binary(id)
    assert %Rule{id: ^id} = VerdictUI.get_rule(id)
  end

  test "to_json_map/1 → JSON → create_rule/1 round-trips a stored rule" do
    attrs =
      @rule_attrs
      |> Map.put(:priority, 3)
      |> Map.put(:sample_facts, %{"player" => %{"team" => "a"}})

    {:ok, rule} = VerdictUI.create_rule(attrs)
    stored = VerdictUI.get_rule(rule.id)

    json = VerdictUI.Rule.to_json_map(stored) |> Jason.encode!()
    {:ok, decoded} = Jason.decode(json)

    {:ok, imported} = VerdictUI.create_rule(decoded)
    reimported = VerdictUI.get_rule(imported.id)

    assert reimported.name == "fouled-out"
    assert reimported.priority == 3
    assert reimported.event.type == "fouledOut"
    assert reimported.event.params == %{"message" => "Player has fouled out!"}
    assert reimported.sample_facts == %{"player" => %{"team" => "a"}}
  end

  test "export_href/1 is a base64 data URI encoding the rule JSON" do
    {:ok, rule} = VerdictUI.create_rule(@rule_attrs)
    stored = VerdictUI.get_rule(rule.id)
    href = VerdictUI.Rule.export_href(stored)

    prefix = "data:application/json;base64,"
    assert String.starts_with?(href, prefix)

    encoded = String.replace_prefix(href, prefix, "")
    {:ok, json} = Base.decode64(encoded)
    {:ok, map} = Jason.decode(json)
    assert map["name"] == "fouled-out"
    assert map["priority"] == 5
  end

  test "create_rule/1 surfaces an event error" do
    attrs = %{event: %{"type" => nil}, conditions: @rule_attrs.conditions}
    {:error, changeset} = VerdictUI.create_rule(attrs)
    # an embeds_one nests its field errors in the embedded changeset
    %Ecto.Changeset{errors: [type: {_msg, _opts}]} = changeset.changes[:event]
  end

  test "create_rule/1 surfaces a conditions error for a bare-leaf root" do
    attrs = %{
      event: %{"type" => "ok"},
      conditions: %{"fact" => "x", "operator" => "equal"}
    }

    {:error, changeset} = VerdictUI.create_rule(attrs)
    assert changeset.errors[:conditions] != nil
  end

  test "update_rule/2" do
    {:ok, rule} = VerdictUI.create_rule(@rule_attrs)
    {:ok, updated} = VerdictUI.update_rule(rule, %{name: "renamed", priority: 3})
    assert updated.name == "renamed"
    assert updated.priority == 3
    assert updated.id == rule.id
  end

  test "list_rules/0 orders by priority desc, then name" do
    VerdictUI.create_rule(%{@rule_attrs | name: "a", priority: 1})
    VerdictUI.create_rule(%{@rule_attrs | name: "b", priority: 9})
    VerdictUI.create_rule(%{@rule_attrs | name: "c", priority: 1})

    [first, second | _] = VerdictUI.list_rules()
    assert first.priority == 9
    assert second.name == "a"
  end

  test "delete_rule/1" do
    {:ok, rule} = VerdictUI.create_rule(@rule_attrs)
    assert VerdictUI.get_rule(rule.id)
    assert {:ok, %Rule{}} = VerdictUI.delete_rule(rule)
    assert VerdictUI.get_rule(rule.id) == nil
  end

  test "to_engine_attrs/1 round-trips a stored rule into a running engine" do
    {:ok, rule} = VerdictUI.create_rule(@rule_attrs)
    stored = VerdictUI.get_rule(rule.id)
    attrs = VerdictUI.Rule.to_engine_attrs(stored)

    engine =
      Verdict.Engine.new()
      |> Verdict.Engine.add_fact("gameDuration", 40)
      |> Verdict.Engine.add_fact("personalFoulCount", 6)

    {:ok, engine, _} = Verdict.Engine.add_rule(engine, attrs)

    %Verdict.RunResult{events: [event]} = Verdict.Engine.run(engine, %{})
    assert event.type == "fouledOut"
  end

  test "create_rule/1 persists sample_facts and to_engine_attrs/1 omits them" do
    attrs =
      @rule_attrs
      |> Map.put(:name, "with-samples")
      |> Map.put(:sample_facts, %{"player" => %{"team" => %{"name" => "a"}}})

    {:ok, rule} = VerdictUI.create_rule(attrs)
    stored = VerdictUI.get_rule(rule.id)
    assert stored.sample_facts == %{"player" => %{"team" => %{"name" => "a"}}}
    assert "sample_facts" not in Map.keys(Rule.to_engine_attrs(stored))
  end

  test "create_rule/1 defaults sample_facts to an empty map" do
    {:ok, rule} = VerdictUI.create_rule(@rule_attrs)
    assert VerdictUI.get_rule(rule.id).sample_facts == %{}
  end

  @scenario_rule_a %{
    name: "sa",
    priority: 2,
    event: %{"type" => "e"},
    conditions: %{"all" => [%{"fact" => "x", "operator" => "equal", "value" => 1}]}
  }

  @scenario_rule_b %{
    name: "sb",
    priority: 1,
    event: %{"type" => "e"},
    conditions: %{"all" => [%{"fact" => "x", "operator" => "greaterThan", "value" => 5}]}
  }

  test "create_scenario/1 with valid data" do
    {:ok, a} = VerdictUI.create_rule(@scenario_rule_a)

    {:ok, scenario} =
      VerdictUI.create_scenario(%{name: "reg", facts: %{"x" => 1}, rule_ids: [a.id]})

    assert scenario.name == "reg"
    assert scenario.facts == %{"x" => 1}
    assert scenario.rule_ids == [a.id]
  end

  test "create_scenario/1 requires a name" do
    {:error, changeset} = VerdictUI.create_scenario(%{facts: %{}, rule_ids: []})
    assert changeset.errors[:name]
  end

  test "update_scenario/2 and delete_scenario/1" do
    {:ok, scenario} = VerdictUI.create_scenario(%{name: "reg"})
    {:ok, updated} = VerdictUI.update_scenario(scenario, %{name: "renamed"})
    assert updated.name == "renamed"
    assert {:ok, %VerdictUI.Scenario{}} = VerdictUI.delete_scenario(updated)
    assert VerdictUI.get_scenario(updated.id) == nil
  end

  test "run_scenario/1 evaluates every associated rule together" do
    {:ok, a} = VerdictUI.create_rule(@scenario_rule_a)
    {:ok, b} = VerdictUI.create_rule(@scenario_rule_b)

    {:ok, scenario} =
      VerdictUI.create_scenario(%{name: "reg", facts: %{"x" => 10}, rule_ids: [a.id, b.id]})

    {:ok, result} = VerdictUI.run_scenario(scenario)
    by_name = Map.new(result["results"], &{&1["name"], &1["result"]})

    # x == 1? no (x is 10)
    assert by_name["sa"] == false
    # x > 5? yes
    assert by_name["sb"] == true
  end

  test "run_scenario/1 drops rules that no longer exist" do
    {:ok, kept} = VerdictUI.create_rule(%{@scenario_rule_a | name: "kept"})
    {:ok, gone} = VerdictUI.create_rule(%{@scenario_rule_a | name: "gone"})

    {:ok, scenario} =
      VerdictUI.create_scenario(%{name: "reg", facts: %{"x" => 1}, rule_ids: [kept.id, gone.id]})

    VerdictUI.delete_rule(gone)

    {:ok, result} = VerdictUI.run_scenario(scenario)
    assert [only] = result["results"]
    assert only["name"] == "kept"
  end

  test "run_opts/1 emits only non-default engine options" do
    assert VerdictUI.run_opts(%{}) == []
    assert VerdictUI.run_opts(%{allow_unsafe: false, allow_undefined_facts: false}) == []
    assert VerdictUI.run_opts(%{report: "full", schedule: "serial", log_level: nil}) == []

    opts =
      VerdictUI.run_opts(%{
        allow_unsafe: true,
        allow_undefined_facts: true,
        allow_undefined_conditions: true,
        strict: true,
        replace_facts_in_event_params: true,
        report: "failures_only",
        schedule: "parallel",
        parallel_concurrency: 4,
        log_level: "debug"
      })

    assert Keyword.get(opts, :allow_unsafe_eex) == true
    assert Keyword.get(opts, :allow_undefined_facts) == true
    assert Keyword.get(opts, :allow_undefined_conditions) == true
    assert Keyword.get(opts, :strict) == true
    assert Keyword.get(opts, :replace_facts_in_event_params) == true
    assert Keyword.get(opts, :report) == :failures_only
    assert Keyword.get(opts, :schedule) == :parallel
    assert Keyword.get(opts, :parallel_concurrency) == 4
    assert Keyword.get(opts, :log) == :debug
  end

  test "create_scenario/1 persists engine options" do
    {:ok, scenario} =
      VerdictUI.create_scenario(%{
        name: "reg",
        allow_undefined_conditions: true,
        strict: true,
        replace_facts_in_event_params: true,
        report: "failures_only",
        schedule: "parallel",
        parallel_concurrency: 4,
        log_level: "debug"
      })

    assert scenario.allow_undefined_conditions == true
    assert scenario.strict == true
    assert scenario.replace_facts_in_event_params == true
    assert scenario.report == "failures_only"
    assert scenario.schedule == "parallel"
    assert scenario.parallel_concurrency == 4
    assert scenario.log_level == "debug"
  end

  test "run_rules/3 orders results by priority desc, then name asc" do
    {:ok, zeta} =
      VerdictUI.create_rule(%{
        name: "zeta",
        priority: 1,
        event: %{"type" => "e"},
        conditions: %{"all" => [%{"fact" => "x", "operator" => "equal", "value" => 1}]}
      })

    {:ok, mid} =
      VerdictUI.create_rule(%{
        name: "mid",
        priority: 2,
        event: %{"type" => "e"},
        conditions: %{"all" => [%{"fact" => "x", "operator" => "equal", "value" => 1}]}
      })

    {:ok, alpha} =
      VerdictUI.create_rule(%{
        name: "alpha",
        priority: 1,
        event: %{"type" => "e"},
        conditions: %{"all" => [%{"fact" => "x", "operator" => "equal", "value" => 1}]}
      })

    {:ok, result} = VerdictUI.run_rules([zeta, mid, alpha], %{"x" => 1}, [])
    names = Enum.map(result["results"], & &1["name"])

    assert names == ["mid", "alpha", "zeta"]
  end
end
