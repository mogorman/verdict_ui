defmodule VerdictUI.LogCapture.Handler do
  @moduledoc false

  # A `:logger` handler that forwards each log event, as a compact `{level, text}`
  # pair, to the capturing process (the LiveView) so a run's engine logs can be
  # shown on the page. `log/2` runs synchronously on the process that issued the
  # event, so the forwarded messages land in the caller's mailbox before the run
  # returns — no async hop, no lost ordering.
  @behaviour :logger_handler

  @impl true
  def log(%{level: level, msg: msg}, %{to: to, sentinel: sentinel}) do
    text = stringify(msg)

    case text do
      ^sentinel -> send(to, :vc_sentinel)
      _ -> send(to, {:vc_log, {level, text}})
    end
  end

  defp stringify({:string, data}), do: IO.iodata_to_binary(data)
  defp stringify({:report, report}), do: inspect(report)
  defp stringify({fmt, args}) when is_binary(fmt) and is_list(args), do: fmt_args(fmt, args)
  defp stringify(msg) when is_binary(msg), do: msg
  defp stringify(msg), do: inspect(msg)

  defp fmt_args(fmt, args), do: IO.iodata_to_binary(:io_lib.format(fmt, args))
end
