defmodule PhoenixAnalytics.Services.Cache do
  @moduledoc """
    This module provides caching functionality for PhoenixAnalytics.

    The main purpose of this cache is to reduce the number of read calls to the database.
    By caching results, we can improve performance and reduce the load on the database
    for frequently accessed data.

    The cache uses Cachex with a TTL read at runtime from
    `PhoenixAnalytics.Config.get_cache_ttl/0`; a TTL of `0` disables caching.
  """

  alias PhoenixAnalytics.Config

  @cache :pa_cache

  @doc false
  @spec name() :: atom()
  def name do
    @cache
  end

  @doc """
  Retrieves a value from the cache for the given key.

  ## Returns

    * `{:ok, nil}` - If the key is not found in the cache.
    * `{:ok, value}` - If the key is found, where `value` is the cached data.

  ## Examples

      iex> PhoenixAnalytics.Services.Cache.get("some_key")
      {:ok, nil}

      iex> PhoenixAnalytics.Services.Cache.get("existing_key")
      {:ok, "cached_value"}
  """
  @spec get(term()) :: {:ok, term()} | {:error, term()}
  def get(key), do: Cachex.get(@cache, key)

  @doc """
  Adds a value to the cache with the given key.

  ## Parameters

    * `key` - The key under which to store the value in the cache.
    * `value` - The value to be stored in the cache.

  ## Returns

    * `{:ok, true}` - If the value was successfully added to the cache.
    * `{:ok, :error}` - If there was an error adding the value to the cache.

  ## Examples

      iex> PhoenixAnalytics.Services.Cache.add("new_key", "new_value")
      {:ok, true}

      iex> PhoenixAnalytics.Services.Cache.add("existing_key", "updated_value")
      {:ok, true}
  """
  @spec add(term(), term()) :: {:ok, boolean()} | {:error, term()}
  def add(key, value), do: Cachex.put(@cache, key, value, expire: expire(Config.get_cache_ttl()))

  @doc """
  Fetches a value from the cache for the given key, or computes and caches it if not present.

  ## Parameters

    * `key` - The key to fetch from the cache.
    * `callback` - A function that computes the value if it's not in the cache.

    ## Returns

      * `{:ok, value}` - If the value was found in the cache.

      * `{:commit, value}` - If the value was successfully computed and cached.

      * `{:ignore, value}` - If the callback returned `{:ignore, value}`, which
        leaves the cache untouched.

      * `{:error, reason}` - If there was an error fetching or computing the value.

  ## Examples

      iex> PhoenixAnalytics.Services.Cache.fetch("some_key", fn -> "computed_value" end)
      {:commit, "computed_value"}

      iex> PhoenixAnalytics.Services.Cache.fetch("existing_key", fn -> "new_value" end)
      {:ok, "cached_value"}
  """
  @spec fetch(term(), (-> term())) ::
          {:ok, term()} | {:commit, term()} | {:ignore, term()} | {:error, term()}
  def fetch(key, callback) do
    ttl = Config.get_cache_ttl()

    if ttl > 0 do
      Cachex.fetch(@cache, key, fn _key -> commit_or_ignore(callback.()) end,
        expire: :timer.seconds(ttl)
      )
    else
      {:ok, unwrap(callback.())}
    end
  end

  @spec expire(non_neg_integer()) :: pos_integer() | nil
  defp expire(0), do: nil
  defp expire(ttl), do: :timer.seconds(ttl)

  # A callback may opt out of caching by returning `{:ignore, value}`, which is
  # how failed reads avoid being cached as if they were valid results.
  @spec commit_or_ignore(term()) :: {:commit, term()} | {:ignore, term()}
  defp commit_or_ignore({:ignore, value}), do: {:ignore, value}
  defp commit_or_ignore(value), do: {:commit, value}

  @spec unwrap(term()) :: term()
  defp unwrap({:ignore, value}), do: value
  defp unwrap(value), do: value
end
