defmodule PhoenixAnalytics.Store.Query do
  @moduledoc """
  Normalized parameters of an analytics query.

  Dates reach the library in many shapes: `Date` structs from tests, ISO strings
  from the dashboard, `NaiveDateTime` from schedulers. They are normalized here,
  once, at the boundary, so every store adapter only ever deals with
  `NaiveDateTime` and a validated interval.
  """

  @type interval :: :hour | :day | :month | :year
  @type date_input :: Date.t() | NaiveDateTime.t() | String.t()

  @type t :: %__MODULE__{
          from: NaiveDateTime.t(),
          to: NaiveDateTime.t(),
          interval: interval(),
          limit: pos_integer() | nil
        }

  @enforce_keys [:from, :to]
  defstruct [:from, :to, interval: :day, limit: nil]

  @intervals ~w(hour day month year)a
  @day_start ~T[00:00:00]
  @day_end ~T[23:59:59]

  @doc """
  Builds a query from any supported date representation.

  A `from` without a time component starts at `00:00:00`, a `to` without a time
  component ends at `23:59:59`, matching the SQL filters used before.

  ## Options

    * `:interval` - `:hour`, `:day`, `:month` or `:year` (also accepted as a
      string, since the dashboard receives it from the client). Defaults to `:day`.
    * `:limit` - maximum number of buckets returned by period queries.

  ## Examples

      iex> query = PhoenixAnalytics.Store.Query.new(~D[2025-01-14], ~D[2025-01-15])
      iex> {query.from, query.to, query.interval}
      {~N[2025-01-14 00:00:00], ~N[2025-01-15 23:59:59], :day}
  """
  @spec new(date_input(), date_input(), keyword()) :: t()
  def new(from, to, opts \\ []) do
    %__MODULE__{
      from: to_naive!(from, @day_start),
      to: to_naive!(to, @day_end),
      interval: opts |> Keyword.get(:interval, :day) |> interval!(),
      limit: Keyword.get(opts, :limit)
    }
  end

  @doc """
  Normalizes a single date input, using `time` when it carries no time of day.

  Shared with `PhoenixAnalytics.Queries.Helpers`, so query filters and store
  adapters accept exactly the same date representations.

  ## Examples

      iex> PhoenixAnalytics.Store.Query.to_naive!(~D[2025-01-15], ~T[23:59:59])
      ~N[2025-01-15 23:59:59]

      iex> PhoenixAnalytics.Store.Query.to_naive!("2025-01-15", ~T[00:00:00])
      ~N[2025-01-15 00:00:00]
  """
  @spec to_naive!(date_input(), Time.t()) :: NaiveDateTime.t()
  def to_naive!(%NaiveDateTime{} = date_time, _time), do: date_time
  def to_naive!(%Date{} = date, time), do: NaiveDateTime.new!(date, time)

  def to_naive!(value, time) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, date_time} ->
        date_time

      {:error, _reason} ->
        value |> String.slice(0, 10) |> Date.from_iso8601!() |> NaiveDateTime.new!(time)
    end
  end

  @spec interval!(interval() | String.t()) :: interval()
  defp interval!(interval) when interval in @intervals, do: interval

  defp interval!(interval) when is_binary(interval) do
    interval |> String.to_existing_atom() |> interval!()
  end
end
