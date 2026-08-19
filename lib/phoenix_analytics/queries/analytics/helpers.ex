defmodule PhoenixAnalytics.Queries.Helpers do
  @moduledoc """
  Ecto query helpers for PhoenixAnalytics analytics queries.

  This module provides helper functions for building Ecto queries
  instead of raw SQL string concatenation.
  """

  import Ecto.Query

  alias PhoenixAnalytics.Filters
  alias PhoenixAnalytics.Store.Query

  @day_start ~T[00:00:00]
  @day_end ~T[23:59:59]

  @doc """
  Excludes non-page requests (static files, assets, etc.) from a query.
  """
  def exclude_non_page(query) do
    query
    |> exclude_static_files()
    |> exclude_asset_paths()
  end

  @doc """
  Excludes development-only paths from a query.
  """
  def exclude_dev(query) do
    query
    |> exclude_dev_paths()
  end

  @doc """
  Applies date range filtering to a query.
  """
  def filter_by_date(query, from_date, to_date) do
    query
    |> filter_from_date(from_date)
    |> filter_to_date(to_date)
  end

  @doc """
  Filters query to only include successful requests (status 200).
  """
  def filter_successful(query) do
    from(r in query, where: r.status_code == 200)
  end

  @doc """
  Filters query to only include GET requests.
  """
  def filter_get_requests(query) do
    from(r in query, where: r.method == "GET")
  end

  @doc """
  Filters query to only include 404 requests.
  """
  def filter_not_found(query) do
    from(r in query, where: r.status_code == 404)
  end

  @doc """
  Filters query to exclude internal referrers.
  """
  def filter_external_referrers(query, app_domain) do
    from(r in query,
      where:
        not like(r.referer, ^"%#{app_domain}%") and
          not like(r.referer, ^"%unknown%")
    )
  end

  # Private helper functions

  @spec exclude_static_files(Ecto.Queryable.t()) :: Ecto.Query.t()
  defp exclude_static_files(query) do
    Enum.reduce(Filters.static_extensions(), query, fn ext, q ->
      from(r in q, where: not like(r.path, ^"%#{ext}"))
    end)
  end

  @spec exclude_asset_paths(Ecto.Queryable.t()) :: Ecto.Query.t()
  defp exclude_asset_paths(query) do
    Enum.reduce(Filters.asset_paths(), query, fn path, q ->
      from(r in q, where: not like(r.path, ^"%#{path}%"))
    end)
  end

  @spec exclude_dev_paths(Ecto.Queryable.t()) :: Ecto.Query.t()
  defp exclude_dev_paths(query) do
    Enum.reduce(Filters.dev_paths(), query, fn path, q ->
      from(r in q, where: not like(r.path, ^"%#{path}%"))
    end)
  end

  @spec filter_from_date(Ecto.Queryable.t(), Query.date_input() | nil) :: Ecto.Queryable.t()
  defp filter_from_date(query, nil), do: query

  defp filter_from_date(query, from_date) do
    from_date = Query.to_naive!(from_date, @day_start)

    from(r in query, where: r.inserted_at >= ^from_date)
  end

  @spec filter_to_date(Ecto.Queryable.t(), Query.date_input() | nil) :: Ecto.Queryable.t()
  defp filter_to_date(query, nil), do: query

  defp filter_to_date(query, to_date) do
    to_date = Query.to_naive!(to_date, @day_end)

    from(r in query, where: r.inserted_at <= ^to_date)
  end
end
