# Seed analytics records with dynamic repo selection
# Run with: mix run priv/repo/seeds.exs [postgres|mysql|sqlite]

Code.require_file("./priv/repo/seed_data.exs")

# Start the application to ensure everything is available
{:ok, _} = Application.ensure_all_started(:phoenix_analytics)

# Get the user's configured repo from command line args
arg = System.argv()
{repo_module, repo_config} = case List.first(arg) do
  "postgres" ->
    {PhoenixAnalyticsDev.PostgresRepo, [
      username: "postgres",
      password: "postgres",
      hostname: "localhost",
      database: "phoenix_postgres_dev",
      stacktrace: true,
      show_sensitive_data_on_connection_error: true,
      pool_size: 10
    ]}
  "mysql" ->
    {PhoenixAnalyticsDev.MysqlRepo, [
      username: "root",
      password: "",
      hostname: "localhost",
      database: "phoenix_mysql_dev",
      stacktrace: true,
      show_sensitive_data_on_connection_error: true,
      pool_size: 10
    ]}
  _ ->
    {PhoenixAnalyticsDev.SqliteRepo, [
      database: Path.expand("../../examples/phoenix_sqlite/phoenix_sqlite_dev.db", __DIR__),
      pool_size: 5,
      stacktrace: true,
      show_sensitive_data_on_connection_error: true
    ]}
end

# Define repo modules locally for seeding with proper configuration
defmodule PhoenixAnalyticsDev.PostgresRepo do
  use Ecto.Repo, otp_app: :phoenix_analytics, adapter: Ecto.Adapters.Postgres
end

defmodule PhoenixAnalyticsDev.MysqlRepo do
  use Ecto.Repo, otp_app: :phoenix_analytics, adapter: Ecto.Adapters.MyXQL
end

defmodule PhoenixAnalyticsDev.SqliteRepo do
  use Ecto.Repo, otp_app: :phoenix_analytics, adapter: Ecto.Adapters.SQLite3
end

# Configure the application environment with the selected repo
Application.put_all_env(
  phoenix_analytics: [
    repo: repo_module,
    app_domain: "example.com",
    cache_ttl: 60
  ]
)

# Start the repo with the proper configuration
{:ok, _} = repo_module.start_link(repo_config)


alias PhoenixAnalytics.Entities.RequestLog

# Run the migration to create tables
PhoenixAnalytics.Migration.up()

batch_size = 5
total_records = case Enum.at(arg, 1) do
  nil -> 1_000_000
  count_str -> String.to_integer(count_str)
end

# Current year date range - used in seed_data.exs for date generation
_current_year = Date.utc_today().year

start_time = System.monotonic_time(:millisecond)

1..total_records
|> Enum.chunk_every(batch_size)
|> Enum.with_index(1)
|> Enum.each(fn {batch, batch_num} ->
  batch_start = System.monotonic_time(:millisecond)

  # Only valid logs are kept, so the store never sees data the schema rejects.
  data_for_insert =
    batch
    |> Task.async_stream(fn _ -> SeedData.generate_request_data() end,
      max_concurrency: System.schedulers_online() * 2
    )
    |> Enum.flat_map(fn {:ok, request_struct} ->
      changeset = RequestLog.changeset(%RequestLog{}, Map.from_struct(request_struct))

      if changeset.valid?, do: [Ecto.Changeset.apply_changes(changeset)], else: []
    end)

  # Insert through the configured store, so seeding works with any adapter
  case PhoenixAnalytics.Store.insert_all(data_for_insert) do
    :ok ->
      batch_time = System.monotonic_time(:millisecond) - batch_start
      total_inserted = batch_num * batch_size
      progress = Float.round(total_inserted / total_records * 100, 1)

      IO.puts("✅ Batch #{batch_num}: #{length(data_for_insert)} records (#{progress}% - #{batch_time}ms)")

    {:error, reason} ->
      IO.puts("❌ Error inserting batch #{batch_num}: #{inspect(reason)}")
  end
end)

total_time = System.monotonic_time(:millisecond) - start_time
records_per_second = round(total_records / (total_time / 1000))

IO.puts("")
IO.puts("🎉 Seeding completed!")
IO.puts("⏱️  Total time: #{Float.round(total_time / 1000, 2)} seconds")
IO.puts("🚀 Speed: #{records_per_second} records/second")

# Verify the data
%{count: final_count} = PhoenixAnalytics.Store.info()
IO.puts("📊 Final record count: #{final_count}")
