defmodule PhoenixAnalytics.Store.ETSTest do
  use ExUnit.Case, async: false

  @table :phoenix_analytics_contract_test

  setup do
    start_supervised!(
      {PhoenixAnalytics.Store.ETS,
       table: @table, prune_interval_ms: :timer.hours(24), retention_days: 3650}
    )

    :ok
  end

  use PhoenixAnalytics.StoreContract,
    store: {PhoenixAnalytics.Store.ETS, table: :phoenix_analytics_contract_test}
end
