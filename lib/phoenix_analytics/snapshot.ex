defmodule PhoenixAnalytics.Snapshot do
  @moduledoc """
  Exports a period of analytics data to a sink, and restores it back.

  Snapshots work with any store that implements the optional `export/3`
  callback, so they are useful both to give the in-memory
  `PhoenixAnalytics.Store.ETS` durability and to archive older data out of a
  database into object storage.

  ## Configuration

      config :phoenix_analytics,
        snapshot: [
          sink: {PhoenixAnalytics.Snapshot.Sink.S3, bucket: "my-analytics", region: "eu-west-1"},
          key_prefix: "phoenix_analytics/",
          every: :day,
          at: ~T[03:00:00],
          window: :previous_day,
          format: :etf,
          gzip: true,
          restore: [days: 7]
        ]

  `PhoenixAnalytics.Snapshot.Scheduler` runs `run/3` on that schedule. Call it
  directly when the schedule is owned by an external job runner such as Oban.
  """

  require Logger

  alias PhoenixAnalytics.Snapshot.Format
  alias PhoenixAnalytics.Store
  alias PhoenixAnalytics.Store.Query

  @type options :: keyword() | map()
  @type result :: %{key: String.t(), count: non_neg_integer(), bytes: non_neg_integer()}

  @defaults %{
    key_prefix: "phoenix_analytics/",
    format: :etf,
    gzip: true,
    restore: false
  }

  @default_restore_days 7
  @epoch ~N[1970-01-01 00:00:00]

  @doc """
  Exports every log of the inclusive period and writes it to the sink.

  Emits `[:phoenix_analytics, :snapshot, :start | :stop | :exception]` telemetry
  events.

  ## Examples

      PhoenixAnalytics.Snapshot.run(~N[2025-08-18 00:00:00], ~N[2025-08-18 23:59:59],
        sink: {PhoenixAnalytics.Snapshot.Sink.Local, path: "tmp/snapshots"})
  """
  @spec run(NaiveDateTime.t(), NaiveDateTime.t(), options()) :: {:ok, result()} | {:error, term()}
  def run(%NaiveDateTime{} = from, %NaiveDateTime{} = to, opts) do
    options = options(opts)
    key = key_for(to, options)
    metadata = %{key: key, from: from, to: to}

    :telemetry.span([:phoenix_analytics, :snapshot], metadata, fn ->
      result = write(from, to, key, options)
      {result, Map.put(metadata, :result, result)}
    end)
  end

  @doc """
  Reloads recent snapshots into the store.

  Only stores implementing `import_all/2` can be restored. Keys that cannot be
  read or decoded are logged and skipped, so one corrupted snapshot does not
  abort the whole restore.
  """
  @spec restore(options()) :: {:ok, non_neg_integer()} | {:error, term()}
  def restore(opts) do
    options = options(opts)
    {sink, sink_opts} = options.sink
    since = Date.to_iso8601(Date.add(Date.utc_today(), -restore_days(options)))

    with {:ok, keys} <- sink.list(options.key_prefix, sink_opts) do
      count =
        keys
        |> Enum.filter(&recent?(&1, options.key_prefix, since))
        |> Enum.sort()
        |> Enum.reduce(0, fn key, acc -> acc + restore_key(key, options) end)

      {:ok, count}
    end
  end

  @doc """
  Normalizes user supplied options into the internal map, applying defaults.

  ## Examples

      iex> options = PhoenixAnalytics.Snapshot.options(sink: {SomeSink, []})
      iex> {options.format, options.gzip}
      {:etf, true}
  """
  @spec options(options()) :: map()
  def options(opts), do: Map.merge(@defaults, Map.new(opts))

  @spec write(NaiveDateTime.t(), NaiveDateTime.t(), String.t(), map()) ::
          {:ok, result()} | {:error, term()}
  defp write(from, to, key, options) do
    {sink, sink_opts} = options.sink

    with {:ok, {body, count}} <- Store.export(Query.new(from, to), &encode(&1, options)),
         :ok <- sink.put(key, body, sink_opts) do
      {:ok, %{key: key, count: count, bytes: IO.iodata_length(body)}}
    end
  end

  @spec encode(Enumerable.t(), map()) :: {iodata(), non_neg_integer()}
  defp encode(logs, options) do
    logs = Enum.to_list(logs)
    body = logs |> Format.encode(options.format) |> compress(options.gzip)

    {body, length(logs)}
  end

  @spec compress(iodata(), boolean()) :: iodata()
  defp compress(body, false), do: body
  defp compress(body, true), do: :zlib.gzip(body)

  @spec key_for(NaiveDateTime.t(), map()) :: String.t()
  defp key_for(to, %{key: {module, function, args}}) do
    apply(module, function, [NaiveDateTime.to_date(to), node() | args])
  end

  defp key_for(to, options) do
    date = to |> NaiveDateTime.to_date() |> Date.to_iso8601()
    extension = Format.extension(options.format, options.gzip)

    "#{options.key_prefix}#{date}/#{node()}.#{extension}"
  end

  @spec restore_days(map()) :: pos_integer()
  defp restore_days(%{restore: restore}) when is_list(restore) do
    Keyword.get(restore, :days, @default_restore_days)
  end

  defp restore_days(_options), do: @default_restore_days

  @spec recent?(String.t(), String.t(), String.t()) :: boolean()
  defp recent?(key, prefix, since) do
    key |> String.replace_prefix(prefix, "") |> String.slice(0, 10) >= since
  end

  @spec restore_key(String.t(), map()) :: non_neg_integer()
  defp restore_key(key, options) do
    {sink, sink_opts} = options.sink

    with {:ok, body} <- sink.get(key, sink_opts),
         {:ok, logs} <- decode(body, key, options),
         {:ok, count} <- Store.import_all(logs) do
      count
    else
      {:error, reason} ->
        Logger.warning("PhoenixAnalytics could not restore #{key}: #{inspect(reason)}")
        0
    end
  end

  @spec decode(binary(), String.t(), map()) :: {:ok, [struct()]} | {:error, term()}
  defp decode(body, key, options) do
    body = if String.ends_with?(key, ".gz"), do: :zlib.gunzip(body), else: body

    {:ok, Format.decode(body, options.format)}
  rescue
    error -> {:error, error}
  end

  @doc false
  @spec epoch() :: NaiveDateTime.t()
  def epoch, do: @epoch
end
