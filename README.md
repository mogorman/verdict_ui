# VerdictUI

A Phoenix LiveView interface for authoring, editing, and testing [Verdict](../verdict) rules, with rules persisted to Postgres. It wraps the `Verdict` engine — the same condition model, event shape, and operator set the engine uses at runtime — so what you build here runs unchanged in your app.

## Rules & conditions

A rule has a `name`, a `priority`, an `event` (`%{"type" => ..., "params" => ...}`), and a `conditions` tree. The condition tree is the engine's JSON form — a recursive mix of:

- `{"all": [...]}` / `{"any": [...]}` — group every / some children
- `{"not": <child>}` — negate a single child
- `{"condition": "name"}` — reference a named condition
- a leaf: `{"fact": "f", "operator": "op", "value": v, "path"?: "...", "params"?: {}}`

The root must be a group, a `not`, or a reference. Built-in operators: `equal`, `notEqual`, `lessThan`, `lessThanInclusive`, `greaterThan`, `greaterThanInclusive`, `in`, `notIn`, `contains`, `doesNotContain`.

## Pages

| Route | Purpose |
|---|---|
| `/` (and `/rules`) | List rules; edit / test / delete |
| `/rules/new` | Create a rule (condition editor + live JSON preview) |
| `/rules/:id/edit` | Edit a rule |
| `/rules/:id/test` | Supply runtime facts and run the rule against the engine |
| `/scenarios` | List scenarios; open / delete |
| `/scenarios/new` | Create a scenario |
| `/scenarios/:id` | Edit a scenario and run it against the engine |

The test page auto-fills the fact names referenced by the rule's conditions; press **Run** and it builds a throwaway `Verdict.Engine`, adds the rule, runs it, and shows whether it fired plus a per-leaf report (expected vs. actual).

### Scenarios

A **scenario** is a saved test case: a name, a set of rules to run together, and the runtime facts to run them with. Use it to evaluate multiple rules at once (e.g. a whole ruleset, or a curated subset) and to re-run saved regression cases.

- `/scenarios/new` (and `/scenarios/:id`) is a unified editor + runner: pick rules with checkboxes, add runtime facts, **Save** to persist, and **Run** to evaluate the selected rules together.
- **Run** builds one engine, adds each selected rule, runs it with the facts, and shows a per-rule result list (fired / not-fired + the leaf report). Rules that no longer exist are dropped at run time.
- A scenario's `facts` must be JSON-encodable (they are stored in a `jsonb` column).

## Standalone development

```sh
mix setup        # deps, DB, migrations, assets
mix phx.server   # → http://localhost:4000
```

Tests (run against a dedicated `verdict_ui_test` Postgres database):

```sh
mix test
mix precommit    # compile --warnings-as-errors, format, test
```

### Tooling note (NixOS / devbox)

The Mix `tailwind` / `esbuild` deps normally download prebuilt dynamically-linked binaries, which NixOS's `stub-ld` blocks. This repo instead auto-discovers `tailwindcss` (v4) and `esbuild` on `PATH` and resolves `daisyui` via `NODE_PATH` from the hex dep. The `devbox` profile provides `tailwindcss_4`, `esbuild`, and `inotify-tools` (for Elixir/template live-reload).

## Embedding in a host app

The embeddable surface is:

- **`VerdictUI`** — a repo-agnostic context (`list_rules/0`, `get_rule/1`, `create_rule/1`, `update_rule/2`, `delete_rule/1`) operating on the `verdict_rules` table.
- **`VerdictUI.Rule`** — the schema, which reuses the engine's `Verdict.Event` and `Verdict.Types.Condition` types.
- **`VerdictUIWeb.*`** — the LiveViews.

### 1. Add the dependency

```elixir
# mix.exs
defp deps do
  [
    {:verdict_ui, path: "../verdict_ui"},
    {:verdict, path: "../verdict"}
  ]
end
```

### 2. Point it at your repo

```elixir
# config/config.exs
config :verdict_ui, repo: MyApp.Repo
```

Without this it defaults to `VerdictUI.Repo`.

### 3. Migrate the table

The migration ships in `priv/repo/migrations/`. Copy `create_verdict_rules.exs` into your app's `priv/repo/migrations/` (or add this project's migrations dir to your `ecto` paths) and run your migrator.

### 4. Mount the routes

Add the rule routes inside a `:browser`-piped scope in your router:

```elixir
# lib/my_app_web/router.ex
scope "/", VerdictUIWeb do
  pipe_through :browser

  live_session :rules do
    live "/rules", VerdictUIWeb.RuleIndexLive
    live "/rules/new", VerdictUIWeb.RuleFormLive, :new
    live "/rules/:id/edit", VerdictUIWeb.RuleFormLive, :edit
    live "/rules/:id/test", VerdictUIWeb.RuleTestLive
  end

  live_session :scenarios do
    live "/scenarios", VerdictUIWeb.ScenarioIndexLive
    live "/scenarios/new", VerdictUIWeb.ScenarioLive
    live "/scenarios/:id", VerdictUIWeb.ScenarioLive
  end
end
```

Rules are stored in their own `verdict_rules` table (not `rules`), so mounting `VerdictUI` does not collide with any `rules` table a host app may already have.

## Project layout

```
lib/verdict_ui.ex              # repo-agnostic context (the embedding seam)
lib/verdict_ui/rule.ex         # schema + changeset (delegates to Verdict.Rule)
lib/verdict_ui/scenario.ex     # scenario schema (named rule-set + saved facts)
lib/verdict_ui/condition_tree.ex  # pure tree mutators + value/path helpers
lib/verdict_ui_web/rule_form_live.ex      # create / edit a rule
lib/verdict_ui_web/rule_index_live.ex     # list / delete rules
lib/verdict_ui_web/rule_test_live.ex      # run a single rule
lib/verdict_ui_web/scenario_live.ex       # scenario editor + multi-rule runner
lib/verdict_ui_web/scenario_index_live.ex # list / delete scenarios
lib/verdict_ui_web/components/condition_editor.ex  # recursive condition editor
lib/verdict_ui_web/components/facts_editor.ex  # shared runtime-fact editor
lib/verdict_ui_web/components/results_list.ex  # shared per-rule results
```
