defmodule VerdictUI.JSON do
  @moduledoc """
  JSON encode/decode backed by Elixir's built-in `:json` module (no Jason).

  Presents the `encode!/decode!/decode` surface the app and Phoenix's
  `:json_library` expect. `:json.decode/1` raises on bad input, so `decode/1`
  wraps it into `{:ok, _} | {:error, _}`. The built-in has no pretty printer,
  so `encode!/2` with `pretty: true` uses a small local one.
  """

  @doc "Encodes `data` to a compact JSON binary."
  def encode!(data), do: IO.iodata_to_binary(encode_to_iodata!(data))

  @doc "Encodes `data` to a pretty-printed (2-space) JSON binary."
  def encode!(data, pretty: true), do: pretty(data)

  def encode!(data, _opts), do: encode!(data)

  @doc "Encodes `data` to JSON iodata (the Phoenix socket-serializer interface)."
  def encode_to_iodata!(data), do: :json.encode(data)

  @doc "Decodes a JSON binary, raising on invalid input."
  def decode!(data), do: :json.decode(data)

  @doc "Decodes a JSON binary, returning `{:ok, term}` or `{:error, reason}`."
  def decode(data) do
    {:ok, :json.decode(data)}
  rescue
    e -> {:error, e}
  end

  # --- minimal 2-space pretty printer for JSON-safe terms (maps/lists/scalars) ---

  defp pretty(term), do: render(term, 0)

  defp render(map, _indent) when is_map(map) and map_size(map) == 0, do: "{}"
  defp render(list, _indent) when is_list(list) and list == [], do: "[]"

  defp render(map, indent) when is_map(map) do
    body =
      map
      |> Enum.map(fn {k, v} ->
        pad(indent + 1) <> jstring(to_string(k)) <> ": " <> render(v, indent + 1)
      end)
      |> Enum.join(",\n")

    "{\n" <> body <> "\n" <> pad(indent) <> "}"
  end

  defp render(list, indent) when is_list(list) do
    body = Enum.map_join(list, ",\n", fn v -> pad(indent + 1) <> render(v, indent + 1) end)
    "[\n" <> body <> "\n" <> pad(indent) <> "]"
  end

  defp render(v, _indent) when is_binary(v), do: jstring(v)
  defp render(nil, _indent), do: "null"
  defp render(true, _indent), do: "true"
  defp render(false, _indent), do: "false"
  defp render(v, _indent) when is_number(v), do: to_string(v)
  defp render(v, _indent), do: IO.iodata_to_binary(:json.encode(v))

  # A quoted, escaped JSON string, delegating escaping to `:json`.
  defp jstring(s), do: IO.iodata_to_binary(:json.encode(s))

  defp pad(0), do: ""
  defp pad(n), do: String.duplicate("  ", n)
end
