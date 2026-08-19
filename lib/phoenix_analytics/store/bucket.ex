defmodule PhoenixAnalytics.Store.Bucket do
  @moduledoc """
  Formats a timestamp into the period label used by charts.

  Every store must label buckets the same way, otherwise the same dashboard
  would render different x axes depending on the backend. SQLite and MySQL
  already return these strings from `strftime`/`DATE_FORMAT`; PostgreSQL and the
  ETS store are normalized here.
  """

  alias PhoenixAnalytics.Store.Query

  @doc """
  Returns the bucket label of a timestamp for the given interval.

  ## Examples

      iex> PhoenixAnalytics.Store.Bucket.key(~N[2025-01-15 13:24:00], :hour)
      "2025-01-15 13:00:00"

      iex> PhoenixAnalytics.Store.Bucket.key(~N[2025-01-15 13:24:00], :month)
      "2025-01"
  """
  @spec key(Date.t() | NaiveDateTime.t() | DateTime.t(), Query.interval()) :: String.t()
  def key(timestamp, :hour), do: Calendar.strftime(timestamp, "%Y-%m-%d %H:00:00")
  def key(timestamp, :day), do: Calendar.strftime(timestamp, "%Y-%m-%d")
  def key(timestamp, :month), do: Calendar.strftime(timestamp, "%Y-%m")
  def key(timestamp, :year), do: Calendar.strftime(timestamp, "%Y")

  @doc """
  Normalizes a value coming from a database into a bucket label.

  Strings are returned untouched, since SQLite and MySQL already format them.
  """
  @spec normalize(String.t() | Date.t() | NaiveDateTime.t() | DateTime.t(), Query.interval()) ::
          String.t()
  def normalize(value, _interval) when is_binary(value), do: value
  def normalize(%Date{} = value, interval), do: key(value, interval)
  def normalize(%NaiveDateTime{} = value, interval), do: key(value, interval)
  def normalize(%DateTime{} = value, interval), do: key(value, interval)
end
