defmodule PhoenixAnalytics.Store.EctoTest do
  use ExUnit.Case, async: false

  alias PhoenixAnalytics.Entities.RequestLog
  alias PhoenixAnalytics.StoreTestRepo

  setup_all do
    {:ok, _pid} = StoreTestRepo.start_link(database: ":memory:", pool_size: 1, log: false)
    :ok = StoreTestRepo.create_requests_table!()

    previous = Application.get_env(:phoenix_analytics, :repo)
    Application.put_env(:phoenix_analytics, :repo, StoreTestRepo)
    on_exit(fn -> Application.put_env(:phoenix_analytics, :repo, previous) end)

    :ok
  end

  setup do
    StoreTestRepo.delete_all(RequestLog)
    :ok
  end

  use PhoenixAnalytics.StoreContract,
    store: {PhoenixAnalytics.Store.Ecto, repo: PhoenixAnalytics.StoreTestRepo}
end
