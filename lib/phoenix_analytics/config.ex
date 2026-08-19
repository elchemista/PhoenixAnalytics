defmodule PhoenixAnalytics.Config do
  @moduledoc """
  Configuration accessors for PhoenixAnalytics.

  Every value is read at runtime so releases can configure the library from
  `config/runtime.exs`.
  """

  @default_store PhoenixAnalytics.Store.Ecto
  @default_app_domain "localhost"
  @default_cache_ttl 120
  @default_batcher [batch_size: 100, flush_interval_ms: 1_000]

  @doc """
  Returns the configured store adapter and its options.

  `:store` takes precedence; the legacy `:repo` key keeps working and selects
  `PhoenixAnalytics.Store.Ecto`.

  ## Examples

      config :phoenix_analytics, repo: MyApp.Repo
      config :phoenix_analytics, store: {PhoenixAnalytics.Store.ETS, retention_days: 30}
  """
  @spec store() :: {module(), keyword()}
  def store do
    case get_config(:store) do
      {module, opts} when is_atom(module) and is_list(opts) -> {module, opts}
      module when is_atom(module) and not is_nil(module) -> {module, []}
      nil -> store_from_repo(get_config(:repo))
    end
  end

  @doc """
  Returns the configured store, or `:error` when none is configured yet.

  Used at boot, where a missing configuration must not keep the host
  application from starting: it is reported when analytics are actually used.
  """
  @spec fetch_store() :: {:ok, {module(), keyword()}} | :error
  def fetch_store do
    if is_nil(get_config(:store)) and is_nil(get_config(:repo)) do
      :error
    else
      {:ok, store()}
    end
  end

  @doc """
  Returns the Ecto repository backing the analytics data.

  Only meaningful when the configured store is `PhoenixAnalytics.Store.Ecto`;
  raises otherwise, since no repository exists for other adapters.
  """
  @spec get_repo() :: module()
  def get_repo do
    case store() do
      {@default_store, opts} -> Keyword.fetch!(opts, :repo)
      {module, _opts} -> raise ArgumentError, no_repo_message(module)
    end
  end

  @doc "Returns the application domain used to filter out internal referrers."
  @spec get_app_domain() :: String.t()
  def get_app_domain, do: get_config(:app_domain, @default_app_domain)

  @doc """
  Returns the dashboard cache TTL in seconds, `0` meaning no caching.

  Read at runtime, so it can come from `config/runtime.exs`. Strings are
  accepted because the value often comes straight from an environment
  variable, as in `cache_ttl: System.get_env("CACHE_TTL")`.
  """
  @spec get_cache_ttl() :: non_neg_integer()
  def get_cache_ttl, do: :cache_ttl |> get_config(@default_cache_ttl) |> to_seconds()

  @doc "Returns the OTP application name."
  @spec get_otp_app() :: atom()
  def get_otp_app, do: get_config(:otp_app, :phoenix_analytics)

  @doc """
  Returns the batching options of `PhoenixAnalytics.Services.Batcher`.

  Defaults to a batch of 100 logs flushed at most every second.
  """
  @spec batcher() :: [batch_size: pos_integer(), flush_interval_ms: pos_integer()]
  def batcher, do: Keyword.merge(@default_batcher, get_config(:batcher, []))

  @doc "Returns the snapshot options, or `nil` when snapshots are disabled."
  @spec snapshot() :: keyword() | nil
  def snapshot, do: get_config(:snapshot)

  @spec to_seconds(term()) :: non_neg_integer()
  defp to_seconds(ttl) when is_integer(ttl) and ttl >= 0, do: ttl

  defp to_seconds(ttl) when is_binary(ttl) do
    case Integer.parse(ttl) do
      {seconds, _rest} when seconds >= 0 -> seconds
      _other -> @default_cache_ttl
    end
  end

  defp to_seconds(_ttl), do: @default_cache_ttl

  @spec store_from_repo(module() | nil) :: {module(), keyword()}
  defp store_from_repo(nil), do: raise(ArgumentError, missing_store_message())
  defp store_from_repo(repo), do: {@default_store, repo: repo}

  @spec missing_store_message() :: String.t()
  defp missing_store_message do
    """
    Phoenix Analytics requires a store to be configured.

    Please add one of the following to your config:

        config :phoenix_analytics,
          repo: MyApp.Repo,
          app_domain: "example.com"

        config :phoenix_analytics,
          store: {PhoenixAnalytics.Store.Ecto, repo: MyApp.Repo},
          app_domain: "example.com"

        config :phoenix_analytics,
          store: {PhoenixAnalytics.Store.ETS, retention_days: 30},
          app_domain: "example.com"
    """
  end

  @spec no_repo_message(module()) :: String.t()
  defp no_repo_message(module) do
    """
    PhoenixAnalytics.Config.get_repo/0 is only available with #{inspect(@default_store)}, \
    but #{inspect(module)} is configured.

    Ecto migrations and SQL queries are specific to the Ecto store; other stores
    manage their own storage.
    """
  end

  @spec get_config(atom(), term()) :: term()
  defp get_config(key, default \\ nil) do
    case Application.fetch_env(:phoenix_analytics, key) do
      {:ok, value} -> value
      :error -> default
    end
  end
end
