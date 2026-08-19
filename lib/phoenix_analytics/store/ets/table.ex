defmodule PhoenixAnalytics.Store.ETS.Table do
  @moduledoc false

  # Thin wrapper around `:ets`. It knows how a request log is keyed and how to
  # walk a time range, and nothing about analytics.

  alias PhoenixAnalytics.Entities.RequestLog

  @typedoc "Key of a stored log: its timestamp in milliseconds plus its id."
  @type key :: {integer(), String.t()}

  @doc "Creates the backing `:ordered_set` table."
  @spec create(atom(), keyword()) :: atom()
  def create(name, opts) do
    options = [
      :ordered_set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ]

    :ets.new(name, options ++ compression(opts))
  end

  @doc "Inserts logs, overwriting any entry with the same key."
  @spec insert(atom(), [RequestLog.t()]) :: :ok
  def insert(name, logs) do
    :ets.insert(name, Enum.map(logs, &{key(&1), &1}))
    :ok
  end

  @doc """
  Streams every log whose timestamp falls inside the inclusive range.

  Walking the ordered set costs only what the range contains, unlike a full
  table scan with a guard.
  """
  @spec stream(atom(), NaiveDateTime.t(), NaiveDateTime.t()) :: Enumerable.t()
  def stream(name, from, to) do
    # `""` sorts before any request id, so it works as an exclusive lower bound
    # and, one millisecond past `to`, as an exclusive upper bound.
    first = {to_milliseconds(from), ""}
    stop = {to_milliseconds(to) + 1, ""}

    Stream.unfold(:ets.next(name, first), fn
      :"$end_of_table" -> nil
      key when key >= stop -> nil
      key -> {lookup!(name, key), :ets.next(name, key)}
    end)
  end

  @doc "Returns every log whose timestamp falls inside the inclusive range."
  @spec range(atom(), NaiveDateTime.t(), NaiveDateTime.t()) :: [RequestLog.t()]
  def range(name, from, to), do: name |> stream(from, to) |> Enum.to_list()

  @doc "Deletes every log older than the given point in time."
  @spec delete_before(atom(), NaiveDateTime.t()) :: non_neg_integer()
  def delete_before(name, point_in_time) do
    milliseconds = to_milliseconds(point_in_time)

    :ets.select_delete(name, [{{{:"$1", :_}, :_}, [{:<, :"$1", milliseconds}], [true]}])
  end

  @doc "Deletes the oldest logs until at most `max_entries` are left."
  @spec trim(atom(), pos_integer()) :: non_neg_integer()
  def trim(name, max_entries) do
    excess = :ets.info(name, :size) - max_entries

    if excess > 0, do: delete_oldest(name, excess), else: 0
  end

  @doc "Returns table statistics: entry count, memory usage and time span."
  @spec info(atom()) :: %{
          count: non_neg_integer(),
          memory_bytes: non_neg_integer(),
          oldest: NaiveDateTime.t() | nil,
          newest: NaiveDateTime.t() | nil
        }
  def info(name) do
    %{
      count: :ets.info(name, :size),
      memory_bytes: :ets.info(name, :memory) * :erlang.system_info(:wordsize),
      oldest: name |> :ets.first() |> key_timestamp(),
      newest: name |> :ets.last() |> key_timestamp()
    }
  end

  @spec compression(keyword()) :: [:compressed]
  defp compression(opts) do
    if Keyword.get(opts, :compressed, false), do: [:compressed], else: []
  end

  @spec key(RequestLog.t()) :: key()
  defp key(%RequestLog{inserted_at: inserted_at, request_id: request_id}) do
    {to_milliseconds(inserted_at), request_id}
  end

  @spec lookup!(atom(), key()) :: RequestLog.t()
  defp lookup!(name, key) do
    [{^key, log}] = :ets.lookup(name, key)
    log
  end

  @spec delete_oldest(atom(), pos_integer()) :: non_neg_integer()
  defp delete_oldest(name, count) do
    Enum.reduce_while(1..count, 0, fn _index, deleted ->
      case :ets.first(name) do
        :"$end_of_table" ->
          {:halt, deleted}

        key ->
          :ets.delete(name, key)
          {:cont, deleted + 1}
      end
    end)
  end

  # Reported at second precision, the same as every stored `inserted_at`, so the
  # two can be compared directly.
  @spec key_timestamp(key() | :"$end_of_table") :: NaiveDateTime.t() | nil
  defp key_timestamp({milliseconds, _request_id}) do
    milliseconds
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
  end

  defp key_timestamp(:"$end_of_table"), do: nil

  @spec to_milliseconds(NaiveDateTime.t()) :: integer()
  defp to_milliseconds(%NaiveDateTime{} = date_time) do
    date_time |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:millisecond)
  end
end
