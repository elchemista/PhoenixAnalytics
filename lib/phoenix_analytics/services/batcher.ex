defmodule PhoenixAnalytics.Services.Batcher do
  @moduledoc """
  Batches `PhoenixAnalytics.Entities.RequestLog` entries before writing them to
  the configured store.

  Logs arrive one per request, but storage is far more efficient in bulk. This
  GenServer accumulates them and flushes either when the batch is full or after
  the flush interval elapses, whichever comes first.

  ## Usage

  To insert a RequestLog:

      PhoenixAnalytics.Services.Batcher.insert(%PhoenixAnalytics.Entities.RequestLog{})

  Alternatively, you can send an event to PubSub for request_log insertion:

      PhoenixAnalytics.Services.PubSub.broadcast(%PhoenixAnalytics.Entities.RequestLog{})

  ## Configuration

      config :phoenix_analytics,
        batcher: [batch_size: 100, flush_interval_ms: 1_000]
  """

  use GenServer

  alias PhoenixAnalytics.Config
  alias PhoenixAnalytics.Entities.RequestLog
  alias PhoenixAnalytics.Services.PubSub
  alias PhoenixAnalytics.Services.Telemetry
  alias PhoenixAnalytics.Store

  @type state :: %{
          batch: [RequestLog.t()],
          batch_size: pos_integer(),
          flush_interval_ms: pos_integer(),
          last_insert_time: integer()
        }

  # --- client callbacks ---

  @doc false
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Inserts a RequestLog into the batch queue.

  The batch is flushed once it reaches the configured size or once the flush
  interval elapses, whichever comes first.

  ## Parameters

    - request_log: A PhoenixAnalytics.Entities.RequestLog struct to be inserted.

  ## Examples

      iex> PhoenixAnalytics.Services.Batcher.insert(%PhoenixAnalytics.Entities.RequestLog{})
      :ok

  Note: You can also use PubSub to insert a RequestLog, which is useful for distributed app scenarios:

      iex> PhoenixAnalytics.Services.PubSub.broadcast(%PhoenixAnalytics.Entities.RequestLog{})
      :ok

  """
  @spec insert(RequestLog.t()) :: :ok
  def insert(request_log) do
    GenServer.cast(__MODULE__, {:insert, request_log})
  end

  # --- server callbacks ---

  @doc false
  @impl GenServer
  def init(_args) do
    # Trapping exits lets terminate/2 run on shutdown, so a partially filled
    # batch is written instead of being lost on every restart or deploy.
    Process.flag(:trap_exit, true)
    PubSub.subscribe()

    options = Config.batcher()
    flush_interval_ms = Keyword.fetch!(options, :flush_interval_ms)
    :timer.send_interval(flush_interval_ms, :check_batch)

    {:ok,
     %{
       batch: [],
       batch_size: Keyword.fetch!(options, :batch_size),
       flush_interval_ms: flush_interval_ms,
       last_insert_time: :os.system_time(:millisecond)
     }}
  end

  @doc false
  @impl GenServer
  def handle_cast({:insert, request_log}, state) do
    batch = [request_log | state.batch]

    if length(batch) >= state.batch_size do
      {:noreply, flush(%{state | batch: batch})}
    else
      {:noreply, %{state | batch: batch}}
    end
  end

  @doc false
  @impl GenServer
  def handle_info({:request_sent, request_log}, state) do
    GenServer.cast(__MODULE__, {:insert, request_log})
    {:noreply, state}
  end

  def handle_info(:check_batch, state) do
    elapsed = :os.system_time(:millisecond) - state.last_insert_time

    if elapsed >= state.flush_interval_ms and match?([_ | _], state.batch) do
      {:noreply, flush(state)}
    else
      {:noreply, state}
    end
  end

  @doc false
  @impl GenServer
  def terminate(_reason, state) do
    flush(state)

    :ok
  end

  @doc """
  Sends a batch of RequestLogs to the configured store.

  Logs are written in insertion order. Failures are reported through telemetry
  and never crash the host application.

  ## Parameters

    - batch: A list of PhoenixAnalytics.Entities.RequestLog structs to be inserted.

  ## Examples

      iex> PhoenixAnalytics.Services.Batcher.send_batch([])
      :ok

  """
  @spec send_batch([RequestLog.t()]) :: :ok
  def send_batch([]), do: :ok

  def send_batch(batch) do
    case Store.insert_all(batch) do
      :ok -> :ok
      {:error, reason} -> Telemetry.log_error(:insert_batch, reason)
    end

    :ok
  end

  # The batch is accumulated by prepending, so it is reversed before writing.
  @spec flush(state()) :: state()
  defp flush(state) do
    state.batch |> Enum.reverse() |> send_batch()

    %{state | batch: [], last_insert_time: :os.system_time(:millisecond)}
  end
end
