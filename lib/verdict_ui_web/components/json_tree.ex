defmodule VerdictUIWeb.Components.JsonTree do
  @moduledoc """
  Renders a decoded JSON value as a collapsible, syntax-highlighted tree.

  Objects and arrays use native `<details>`/`<summary>` so any node folds and
  expands without JavaScript; scalar values are colored by type. Every node
  starts open to mirror a pretty-printed dump.
  """
  use VerdictUIWeb, :html

  @doc "Renders `value` (a decoded JSON term) as a foldable, highlighted tree."
  def json_tree(assigns) do
    ~H"""
    <div class="text-xs leading-5">
      <.value value={@value} />
    </div>
    """
  end

  # A single value: object, array, or a colored scalar.
  def value(assigns) do
    ~H"""
    <.object :if={is_map(@value)} map={@value} />
    <.array :if={is_list(@value)} list={@value} />
    <span :if={!is_map(@value) and !is_list(@value)} class={scalar_class(@value)}>
      {scalar_text(@value)}
    </span>
    """
  end

  def object(assigns) do
    ~H"""
    <details open>
      <summary class="cursor-pointer select-none">
        <span class="text-zinc-400 dark:text-zinc-500"><%= "{" %></span>
        <span class="text-zinc-500 dark:text-zinc-400">{map_size(@map)}</span>
        <span class="text-zinc-400 dark:text-zinc-500"><%= "}" %></span>
      </summary>

      <div class="ml-1 border-l border-zinc-300 pl-3 dark:border-zinc-700">
        <div :for={{k, v} <- @map}>
          <span class="text-sky-700 dark:text-sky-300">"{k}"</span>
          <span class="text-zinc-400 dark:text-zinc-500">: </span>
          <.value value={v} />
        </div>
      </div>
    </details>
    """
  end

  def array(assigns) do
    ~H"""
    <details open>
      <summary class="cursor-pointer select-none">
        <span class="text-zinc-400 dark:text-zinc-500">[</span>
        <span class="text-zinc-500 dark:text-zinc-400">{length(@list)}</span>
        <span class="text-zinc-400 dark:text-zinc-500">]</span>
      </summary>

      <div class="ml-1 border-l border-zinc-300 pl-3 dark:border-zinc-700">
        <div :for={v <- @list}>
          <.value value={v} />
        </div>
      </div>
    </details>
    """
  end

  defp scalar_class(nil), do: "text-zinc-500 dark:text-zinc-400"
  defp scalar_class(v) when is_boolean(v), do: "text-purple-700 dark:text-purple-300"
  defp scalar_class(v) when is_number(v), do: "text-amber-700 dark:text-amber-300"
  defp scalar_class(v) when is_binary(v), do: "text-green-700 dark:text-green-300"
  defp scalar_class(_), do: "text-zinc-700 dark:text-zinc-200"

  defp scalar_text(nil), do: "null"
  defp scalar_text(v) when is_boolean(v), do: to_string(v)
  defp scalar_text(v) when is_binary(v), do: "\"#{v}\""
  defp scalar_text(v), do: to_string(v)
end
