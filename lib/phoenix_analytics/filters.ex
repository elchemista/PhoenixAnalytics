defmodule PhoenixAnalytics.Filters do
  @moduledoc """
  Pure classification rules for tracked requests.

  These rules define what counts as a page, a static asset, a development path
  or an external referer. They are shared by every store adapter: the Ecto
  adapter turns them into `LIKE` clauses while the ETS adapter applies them as
  plain predicates, so both backends agree on what a "pageview" is.

  This module contains no infrastructure and can be tested in isolation.
  """

  @static_extensions ~w(.js .css .png .jpg .jpeg .svg .gif .woff .woff2 .ttf .ico .txt .xml)
  @asset_paths ~w(/uploads/ /assets/ /images/ /css/ /js/ /fonts/ /favicon.ico)
  @dev_paths ~w(/phoenix/live_reload/ /dev/)
  @resource_markers ~w(.js .css .png .jpg .svg .gif .woff .ico)

  @doc "File extensions served as static assets."
  @spec static_extensions() :: [String.t()]
  def static_extensions, do: @static_extensions

  @doc "Path fragments used by asset pipelines."
  @spec asset_paths() :: [String.t()]
  def asset_paths, do: @asset_paths

  @doc "Path fragments only reachable in development."
  @spec dev_paths() :: [String.t()]
  def dev_paths, do: @dev_paths

  @doc "Returns true when the path points to a static asset file."
  @spec static_asset?(String.t()) :: boolean()
  def static_asset?(path) when is_binary(path) do
    Enum.any?(@static_extensions, &String.ends_with?(path, &1))
  end

  @doc "Returns true when the path belongs to an asset directory."
  @spec asset_path?(String.t()) :: boolean()
  def asset_path?(path) when is_binary(path) do
    Enum.any?(@asset_paths, &String.contains?(path, &1))
  end

  @doc "Returns true when the path is only used during development."
  @spec dev_path?(String.t()) :: boolean()
  def dev_path?(path) when is_binary(path) do
    Enum.any?(@dev_paths, &String.contains?(path, &1))
  end

  @doc """
  Returns true when the path represents a page rather than an asset.

  Mirrors `PhoenixAnalytics.Queries.Helpers.exclude_non_page/1`.
  """
  @spec page_path?(String.t()) :: boolean()
  def page_path?(path) when is_binary(path) do
    not static_asset?(path) and not asset_path?(path)
  end

  @doc """
  Returns true when the request counts as a pageview.

  Mirrors the SQL pipeline `filter_get_requests |> filter_successful |> exclude_non_page`.
  """
  @spec pageview?(map()) :: boolean()
  def pageview?(%{method: "GET", status_code: 200, path: path}) when is_binary(path) do
    page_path?(path)
  end

  def pageview?(_request), do: false

  @doc """
  Returns true when the referer points outside of `app_domain`.

  A missing referer is excluded, matching SQL where `NULL LIKE` never holds.
  """
  @spec external_referer?(String.t() | nil, String.t()) :: boolean()
  def external_referer?(nil, _app_domain), do: false

  def external_referer?(referer, app_domain) when is_binary(referer) do
    not String.contains?(referer, app_domain) and not String.contains?(referer, "unknown")
  end

  @doc """
  Returns true when the path is a resource rather than a page.

  Mirrors the predicate used by `PhoenixAnalytics.Queries.Analytics.Charts.Slowest.slowest_resources/2`.
  """
  @spec resource_path?(String.t()) :: boolean()
  def resource_path?(path) when is_binary(path) do
    not String.contains?(path, "/") or Enum.any?(@resource_markers, &String.contains?(path, &1))
  end
end
