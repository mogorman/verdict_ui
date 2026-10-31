defmodule VerdictUI.LogCapture do
  @moduledoc """
  Captures the `Logger` output produced while `fun` runs and returns it together
  with `fun`'s own result: `{result, lines}` where `lines` is a list of
  `{level, message}` tuples in emit order. This lets a caller surface the
  verdict engine's run logs on the page instead of only to the console.

  A temporary `:logger` handler (`LogCapture.Handler`) forwards each event to the
  calling process. `:logger` invokes the handler synchronously on the process
  that issued the event, so every forwarded message — including the trailing
  sentinel, which the caller emits last — is already in the caller's mailbox by
  the time the run returns. The handler is always removed, even if `fun` raises.

  ## Caveats

  - Only one capture may be in flight at a time (the handler id is fixed). A
    concurrent capture runs without capturing instead of failing.
  - The sentinel is emitted at `:debug`; if the app's logger level filters it
    out, the drain falls back to a short timeout and returns whatever arrived.
  """
  require Logger

  @handler_id :verdict_ui_capture
  @sentinel "__VERDICT_UI_LOG_CAPTURE_SENTINEL__"
  @drain_timeout 100

  @doc "Runs `fun` and returns `{result, captured_lines}`."
  def capture(fun) do
    me = self()

    case :logger.add_handler(@handler_id, __MODULE__.Handler, %{to: me, sentinel: @sentinel}) do
      :ok ->
        try do
          result = fun.()
          Logger.debug(@sentinel)
          {result, drain([])}
        after
          :logger.remove_handler(@handler_id)
        end

      {:error, _} ->
        {fun.(), []}
    end
  end

  # Drains captured lines until the sentinel. Non-vc messages are left in the
  # mailbox untouched. The timeout is a backstop for a level-filtered sentinel.
  defp drain(acc) do
    receive do
      {:vc_log, entry} -> drain([entry | acc])
      :vc_sentinel -> Enum.reverse(acc)
    after
      @drain_timeout -> Enum.reverse(acc)
    end
  end
end
