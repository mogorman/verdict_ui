defmodule VerdictUIWeb.Components.JsonPathPicker do
  @moduledoc """
  A picker that drills into a fact's sample JSON value and emits the JSONPath for
  any node, plus the equivalent EEx snippet for events. Purely presentational: it
  renders a flat, indented list of every addressable node. Each node emits
  `pick-node` (button `value` = the chosen JSONPath); when the fact has no sample
  it offers a paste box (`picker-paste`, `name="sample"`) to add one.
  """
  use VerdictUIWeb, :html

  attr :fact, :string, required: true
  attr :sample, :any, default: nil

  def picker(assigns) do
    ~H"""
    <div id="jsonpath-picker" class="mt-2 rounded-md border border-base-300 bg-base-100 p-3">
      <div class="mb-2 flex items-center justify-between">
        <p class="text-sm font-semibold">
          Pick a path for <span class="font-mono">{@fact}</span>
        </p>
        <button type="button" class="btn btn-ghost btn-xs" phx-click="close-picker">
          close
        </button>
      </div>

      <form :if={@sample == nil} phx-submit="picker-paste" class="space-y-2">
        <p class="text-sm text-base-content/60">
          No sample for this fact yet. Paste a sample JSON value to drill into it.
        </p>

        <div class="flex gap-2">
          <input
            type="text"
            name="sample"
            placeholder='{"team":{"name":"a"}}'
            class="flex-1 input input-sm font-mono text-sm"
          />
          <button type="submit" class="btn btn-ghost btn-sm shrink-0">use sample</button>
        </div>
      </form>

      <div :if={@sample != nil} class="space-y-0.5 font-mono text-xs">
        <div :for={row <- paths(@sample, @fact)} class="flex items-center gap-2">
          <span style={"padding-left: #{row.depth}rem"}>
            <button
              type="button"
              class="btn btn-ghost btn-xs"
              phx-click="pick-node"
              value={row.path}
            >
              {row.path}
            </button>
          </span>
          <span class="ml-auto truncate text-base-content/50">{row.eex}</span>
        </div>
      </div>
    </div>
    """
  end

  # --- path enumeration --------------------------------------------------------

  defp paths(value, fact), do: walk(value, "$", eex_root(fact), 0)

  defp walk(value, jp, eex, depth) do
    [row(jp, eex, depth) | children(value, jp, eex, depth)]
  end

  defp row(jp, eex, depth), do: %{path: jp, eex: eex, depth: depth}

  defp children(m, jp, eex, depth) when is_map(m) do
    m
    |> Map.keys()
    |> Enum.sort()
    |> Enum.flat_map(fn k ->
      walk(Map.fetch!(m, k), jp <> key_seg(k), eex <> ~s|["#{k}"]|, depth + 1)
    end)
  end

  defp children(l, jp, eex, depth) when is_list(l) do
    l
    |> Enum.with_index()
    |> Enum.flat_map(fn {v, i} -> walk(v, jp <> "[#{i}]", eex <> "[#{i}]", depth + 1) end)
  end

  defp children(_scalar, _jp, _eex, _depth), do: []

  defp eex_root(fact), do: ~s|facts["#{fact}"]|

  # A safe identifier keys with a dot (`$.a`); anything else uses bracket access
  # (`$['weird key']`), which the engine's JSONPath normalizer accepts.
  defp key_seg(key) when is_binary(key) do
    if String.match?(key, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/), do: ".#{key}", else: "['#{key}']"
  end
end
