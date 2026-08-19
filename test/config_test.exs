defmodule PhoenixAnalytics.ConfigTest do
  use ExUnit.Case, async: false

  alias PhoenixAnalytics.Config

  setup do
    previous = Application.get_all_env(:phoenix_analytics)

    on_exit(fn ->
      Application.delete_env(:phoenix_analytics, :store)
      Application.delete_env(:phoenix_analytics, :repo)

      Enum.each(previous, fn {key, value} ->
        Application.put_env(:phoenix_analytics, key, value)
      end)
    end)

    :ok
  end

  describe "store/0" do
    test "maps the legacy repo option to the Ecto store" do
      Application.delete_env(:phoenix_analytics, :store)
      Application.put_env(:phoenix_analytics, :repo, MyApp.Repo)

      assert Config.store() == {PhoenixAnalytics.Store.Ecto, repo: MyApp.Repo}
      assert Config.get_repo() == MyApp.Repo
    end

    test "takes the store option over the repo one" do
      Application.put_env(:phoenix_analytics, :repo, MyApp.Repo)
      Application.put_env(:phoenix_analytics, :store, {PhoenixAnalytics.Store.ETS, table: :t})

      assert Config.store() == {PhoenixAnalytics.Store.ETS, table: :t}
    end

    test "accepts a bare module" do
      Application.put_env(:phoenix_analytics, :store, PhoenixAnalytics.Store.ETS)

      assert Config.store() == {PhoenixAnalytics.Store.ETS, []}
    end

    test "explains how to configure a store when none is set" do
      Application.delete_env(:phoenix_analytics, :store)
      Application.delete_env(:phoenix_analytics, :repo)

      assert_raise ArgumentError, ~r/requires a store to be configured/, &Config.store/0
    end

    test "get_repo/0 refuses stores that have no repository" do
      Application.put_env(:phoenix_analytics, :store, {PhoenixAnalytics.Store.ETS, []})

      assert_raise ArgumentError, ~r/only available with/, &Config.get_repo/0
    end
  end

  describe "fetch_store/0" do
    test "returns an error instead of raising, so the application still boots" do
      Application.delete_env(:phoenix_analytics, :store)
      Application.delete_env(:phoenix_analytics, :repo)

      assert Config.fetch_store() == :error
    end

    test "returns the configured store" do
      Application.put_env(:phoenix_analytics, :repo, MyApp.Repo)

      assert Config.fetch_store() == {:ok, {PhoenixAnalytics.Store.Ecto, repo: MyApp.Repo}}
    end
  end

  describe "batcher/0" do
    test "merges user options over the defaults" do
      Application.put_env(:phoenix_analytics, :batcher, batch_size: 5)

      assert Keyword.fetch!(Config.batcher(), :batch_size) == 5
      assert Keyword.fetch!(Config.batcher(), :flush_interval_ms) == 1_000
    end
  end
end
