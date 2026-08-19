defmodule PhoenixAnalytics.Snapshot.Scheduler do
  @moduledoc """
  Runs `PhoenixAnalytics.Snapshot.run/3` on a recurring schedule.

  Started automatically when `config :phoenix_analytics, snapshot: [...]` is
  present. It also triggers the optional restore at boot, in a supervised task
  so the application starts immediately.

  ## Options

  Every option of `PhoenixAnalytics.Snapshot`, plus:

    * `:every` - `:day`, `{:hours, n}`, `{:minutes, n}` or `:manual`. Defaults to `:day`.
    * `:at` - UTC time of the daily run. Defaults to `~T[03:00:00]`.
    * `:window` - `:previous_day`, `:since_last` or `:all`. Defaults to `:previous_day`.
    * `:run_on` - `:all`, `{:node, node}` or an MFA returning a boolean, to keep
      a cluster from writing the same snapshot several times. Defaults to `:all`.

  With `every: :manual` nothing is scheduled and snapshots are triggered by
  `run_now/0` or by calling `PhoenixAnalytics.Snapshot.run/3` from a job runner.
  """

  use GenServer

  require Logger

  alias PhoenixAnalytics.Snapshot
  alias PhoenixAnalytics.Store

  @defaults [every: :day, at: ~T[03:00:00], window: :previous_day, run_on: :all]

  @type state :: map()

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, Keyword.merge(@defaults, opts), name: __MODULE__)
  end

  @doc """
  Runs a snapshot immediately, using the configured window.

  ## Examples

      iex> PhoenixAnalytics.Snapshot.Scheduler.run_now()
      :ok
  """
  @spec run_now() :: :ok
  def run_now, do: GenServer.call(__MODULE__, :run_now, :infinity)

  @doc false
  @impl GenServer
  def init(opts) do
    state = opts |> Map.new() |> Map.put(:last_to, nil)
    restore_async(state)

    {:ok, schedule(state)}
  end

  @doc false
  @impl GenServer
  def handle_call(:run_now, _from, state), do: {:reply, :ok, run(state)}

  @doc false
  @impl GenServer
  def handle_info(:tick, state) do
    state = if run_here?(state.run_on), do: run(state), else: state

    {:noreply, schedule(state)}
  end

  @spec run(state()) :: state()
  defp run(state) do
    {from, to} = window(state)

    case Snapshot.run(from, to, state) do
      {:ok, snapshot} ->
        Logger.info("PhoenixAnalytics wrote #{snapshot.count} records to #{snapshot.key}")
        %{state | last_to: to}

      {:error, reason} ->
        Logger.warning("PhoenixAnalytics snapshot failed: #{inspect(reason)}")
        state
    end
  end

  # Restoring in a task keeps a large snapshot from delaying application boot.
  @spec restore_async(state()) :: :ok
  defp restore_async(%{restore: restore} = state) when is_list(restore) do
    if Store.supports?(:import_all) do
      Task.Supervisor.start_child(PhoenixAnalytics.Application.task_supervisor(), fn ->
        Snapshot.restore(state)
      end)
    end

    :ok
  end

  defp restore_async(_state), do: :ok

  @spec schedule(state()) :: state()
  defp schedule(%{every: :manual} = state), do: state

  defp schedule(state) do
    Process.send_after(self(), :tick, milliseconds_until_next(state.every, state.at))
    state
  end

  @spec milliseconds_until_next(
          :day | {:hours, pos_integer()} | {:minutes, pos_integer()},
          Time.t()
        ) ::
          pos_integer()
  defp milliseconds_until_next({:hours, hours}, _at), do: :timer.hours(hours)
  defp milliseconds_until_next({:minutes, minutes}, _at), do: :timer.minutes(minutes)

  defp milliseconds_until_next(:day, at) do
    now = DateTime.utc_now()
    today = DateTime.new!(DateTime.to_date(now), at)
    next = if DateTime.compare(today, now) == :gt, do: today, else: DateTime.add(today, 1, :day)

    DateTime.diff(next, now, :millisecond)
  end

  @spec window(state()) :: {NaiveDateTime.t(), NaiveDateTime.t()}
  defp window(%{window: :previous_day}) do
    day = Date.add(Date.utc_today(), -1)

    {NaiveDateTime.new!(day, ~T[00:00:00]), NaiveDateTime.new!(day, ~T[23:59:59])}
  end

  defp window(%{window: :since_last, last_to: %NaiveDateTime{} = last_to}) do
    {NaiveDateTime.add(last_to, 1, :second), now()}
  end

  defp window(_state), do: {Snapshot.epoch(), now()}

  @spec run_here?(:all | {:node, node()} | {module(), atom(), list()}) :: boolean()
  defp run_here?(:all), do: true
  defp run_here?({:node, name}), do: node() == name
  defp run_here?({module, function, args}), do: apply(module, function, args) == true

  @spec now() :: NaiveDateTime.t()
  defp now, do: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
end
