# 📊 Phoenix Analytics

<p align="center">
  <a title="GitHub CI" href="https://github.com/lalabuy948/PhoenixAnalytics/actions"><img src="https://github.com/lalabuy948/PhoenixAnalytics/actions/workflows/tests.yml/badge.svg" alt="GitHub CI" /></a>
  <a title="Latest release" href="https://hex.pm/packages/phoenix_analytics"><img src="https://img.shields.io/hexpm/v/phoenix_analytics.svg" alt="Latest release" /></a>
  <a title="View documentation" href="https://hexdocs.pm/phoenix_analytics"><img src="https://img.shields.io/badge/hex.pm-docs-blue.svg" alt="View documentation" /></a>
</p>

> [!IMPORTANT]
> **Version 0.4.0 Breaking Changes**: The 🦆 duck has been removed. Users who prefer the duckdb version should use the maintained fork: [**PhoenixAnalyticsDuck**](https://github.com/lalabuy948/PhoenixAnalyticsDuck)

![](https://raw.githubusercontent.com/lalabuy948/PhoenixAnalytics/master/github/hero.png)

![](https://raw.githubusercontent.com/lalabuy948/PhoenixAnalytics/master/github/screenshot.png)

Phoenix Analytics is embedded plug and play tool designed for Phoenix applications. It provides a simple and efficient way to track and analyze user behavior and application performance without impacting your main application's performance and database.

Key features:
- ⚡️ Lightweight and fast analytics tracking
- 🗄️ Flexible storage: PostgreSQL, SQLite3, MySQL, in-memory ETS, or your own adapter
- 📦 Periodic snapshots to S3 or to any sink you plug in
- 🔌 Easy integration with Phoenix applications, with an extensible tracking plug
- 📊 Minimalistic dashboard for data visualization
- 🎨 12 customizable color themes
- 🌙 Full dark mode support across all themes

> Phoenix Analytics now supports multiple database backends using Ecto, allowing you to choose the database that best fits your deployment environment and requirements. Whether you're using PostgreSQL in production, SQLite3 for development, or MySQL in your infrastructure, Phoenix Analytics will work seamlessly.

## Installation

If [available in Hex](https://hex.pm/packages/phoenix_analytics), the package can be installed
by adding `phoenix_analytics` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_analytics, "~> 0.4"}
  ]
end
```

### Configuration

Phoenix Analytics uses your existing Ecto repository, making setup incredibly simple:

```elixir
# config/dev.exs
config :phoenix_analytics,
  repo: MyApp.Repo,
  app_domain: System.get_env("PHX_HOST") || "example.com",
  cache_ttl: System.get_env("CACHE_TTL") || 60
```

See [Stores](#stores) to keep analytics out of your database entirely.

### Migration

Create the analytics table in your existing database:

```sh
mix ecto.gen.migration add_phoenix_analytics
```

```elixir
defmodule MyApp.Repo.Migrations.AddPhoenixAnalytics do
  use Ecto.Migration

  def up, do: PhoenixAnalytics.Migration.up()
  def down, do: PhoenixAnalytics.Migration.down()
end

# indexes, no sqlite support
defmodule MyApp.Repo.Migrations.AddPhoenixAnalyticsIndexes do
  def change do
    PhoenixAnalytics.Migration.add_indexes()
  end
end
```

```sh
mix ecto.migrate
```

> **Alternative**: If you don't use migrations, you can run the migration directly:
> 
> ```elixir
> iex -S mix
> PhoenixAnalytics.Migration.up()
> ```

Add plug to enable tracking to `endpoint.ex`, ‼️ add it straight after your `Plug.Static`

```elixir
plug PhoenixAnalytics.Plugs.RequestTracker
```

Add dashboard route to your `router.ex`

```elixir
use PhoenixAnalytics.Web, :router

phoenix_analytics_dashboard "/analytics"
```

> [!WARNING]
> ‼️ Please test thoroughly before proceeding to production!

## Stores

Storage is pluggable. `repo:` above is shorthand for the Ecto store; the full
form lets you pick another adapter:

```elixir
# Your database, through your existing repo (default)
config :phoenix_analytics, store: {PhoenixAnalytics.Store.Ecto, repo: MyApp.Repo}

# In memory, no database at all
config :phoenix_analytics,
  store: {PhoenixAnalytics.Store.ETS, retention_days: 30, max_entries: 2_000_000},
  cache_ttl: 0
```

| | `Store.Ecto` | `Store.ETS` |
| --- | --- | --- |
| Storage | your database | node memory (~0.5-1 KB per request) |
| Survives a restart | yes | only what was snapshotted |
| Multiple nodes | shared | one data set per node |
| Migrations | required | none |
| Dashboard reads | SQL | in-memory folds, no query cost |

With the ETS store, keep memory bounded with `:retention_days` and
`:max_entries`, check `PhoenixAnalytics.Store.info/0` for current usage, and add
[snapshots](#snapshots) for durability.

Writing your own store means implementing the `PhoenixAnalytics.Store`
behaviour, one callback per analytics operation, and pointing the config at it:

```elixir
config :phoenix_analytics, store: {MyApp.AnalyticsStore, url: "..."}
```

## Snapshots

Any store implementing the optional `export/3` callback can be snapshotted on a
schedule, which is what gives the ETS store durability and what archives older
rows out of a database:

```elixir
config :phoenix_analytics,
  snapshot: [
    sink: {PhoenixAnalytics.Snapshot.Sink.S3, bucket: "my-analytics", region: "eu-west-1"},
    every: :day,             # :day | {:hours, n} | {:minutes, n} | :manual
    at: ~T[03:00:00],        # UTC
    window: :previous_day,   # :previous_day | :since_last | :all
    format: :etf,            # :etf to restore, :jsonl for Athena/DuckDB/BigQuery
    gzip: true,
    run_on: :all,            # :all | {:node, :"app@host"} | {Mod, :fun, []}
    restore: [days: 7]       # reload recent snapshots at boot (ETS store)
  ]
```

The S3 sink needs [ExAws](https://hex.pm/packages/ex_aws) in your application:

```elixir
{:ex_aws, "~> 2.5"}, {:ex_aws_s3, "~> 2.5"}, {:req, "~> 0.5"}, {:sweet_xml, "~> 0.7"}
```

For development, or for hosts with a backed up volume, write to disk instead:

```elixir
sink: {PhoenixAnalytics.Snapshot.Sink.Local, path: "tmp/snapshots"}
```

With `every: :manual` nothing is scheduled and you trigger the export yourself,
for example from an Oban job:

```elixir
PhoenixAnalytics.Snapshot.run(from, to, Application.get_env(:phoenix_analytics, :snapshot))
```

Any other destination is a `PhoenixAnalytics.Snapshot.Sink` implementation:
`put/3`, `get/2`, `list/2` and `delete/2`.

## Customizing the tracker

`PhoenixAnalytics.Plugs.RequestTracker` takes options when you need more control
than plug and play:

```elixir
plug PhoenixAnalytics.Plugs.RequestTracker,
  before: [MyApp.Plugs.ConsentCheck, {MyApp.Plugs.BotFilter, min_score: 3}],
  after: [MyApp.Plugs.AnalyticsHeaders],
  filter: {MyApp.Analytics, :track?, []},
  transform: {MyApp.Analytics, :enrich, []},
  ignore_paths: ["/health", "/metrics", ~r{^/admin/}],
  session: [cookie_name: "pa_session_id", max_age: 300, same_site: "Lax"]
```

| Option | Purpose |
| --- | --- |
| `:before` | plugs run before tracking starts |
| `:after` | plugs run once tracking is armed, with the session available |
| `:filter` | `{Mod, :fun, args}` receiving the conn; `false` skips the request |
| `:transform` | `{Mod, :fun, args}` receiving the log and the conn; `nil` drops it |
| `:ignore_paths` | path prefixes or regexes never tracked |
| `:session` | cookie names, `:max_age`, `:same_site`, `:secure`, `:http_only` |

The session cookies are client controlled, so the page view counter is parsed
defensively and capped: a malformed or oversized value restarts the count
instead of failing the request or the insert batch behind it.

Callbacks are `{module, function, args}` tuples because endpoints build plug
options at compile time, where a closure cannot exist.

A `:before` plug decides whether the request is tracked at all:

```elixir
defmodule MyApp.Plugs.ConsentCheck do
  @behaviour Plug

  import PhoenixAnalytics.Plugs

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if analytics_consent?(conn), do: conn, else: skip(conn)
  end
end
```

And a `:transform` callback enriches or drops the log before it is stored:

```elixir
defmodule MyApp.Analytics do
  def track?(conn), do: not bot?(conn)

  def enrich(log, conn) do
    if internal?(conn), do: nil, else: %{log | path: normalize(log.path)}
  end
end
```

Tracking emits `[:phoenix_analytics, :request, :tracked]` and
`[:phoenix_analytics, :request, :skipped]` telemetry events, and never lets an
error reach the request.

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm/phoenix_analytics). Once published, the docs can
be found at <https://hexdocs.pm/phoenix_analytics>.

Shortcuts:

- `t` -> today
- `ctrl+t` -> yesterday
- `w` -> last_week
- `m` -> last_30_days
- `q` -> last_90_days
- `y` -> last_12_month
- `ctrl+w` -> previous_week
- `ctrl+m` -> previous_month
- `ctrl+q` -> previous_quarter
- `ctrl+y` -> previous_year
- `a` -> all_time

### Development

If you would like to contribute, first you would need to install deps, assets and then compile css and js.
I put everything under next mix command:

```sh
mix setup
```

Then you would need some database with seeds. Here is command for this:

```sh
# For SQLite3
mix run priv/repo/seeds.exs sqlite 10000

# For PostgreSQL
mix run priv/repo/seeds.exs postgres

# For MySQL
mix run priv/repo/seeds.exs mysql 10000
```

> [!NOTE]
> Move database with seeds to example project which you going to use.

Lastly you can use one of example applications to start server.

```sh
cd examples/sqlite/

mix deps.get

mix phx.server
```

You can navigate to `http://localhost:4000/dev/analytics`

## Performance test

I performed [vegeta](https://github.com/tsenart/vegeta) test on basic Macbook Air M2, to see if plug will affect application performance.
Script can be found here: `vegeta/vegeta.sh`

| With plug              | Without                |
| ---------------------- | ---------------------- |
| ![with](/github/vegeta-with.png) | ![without](/github/vegeta-without.png) |

## For whom this library

- [x] Single instance Phoenix app (any supported database, or the ETS store)
- [x] Multiple instances of Phoenix app **without** auto scaling group (any supported database)
- [x] Multiple instances of Phoenix app **with** auto scaling group (PostgreSQL or MySQL)

> The ETS store keeps one data set per node, so on multiple instances each node
> reports its own traffic. Use a shared database, or snapshot each node with the
> node name in the key, when you need a single view.

### Heavily inspired by

- [error-tracker](https://github.com/elixir-error-tracker/error-tracker)
- [plausible.io](https://plausible.io)

### Star History

[![Star History Chart](https://api.star-history.com/svg?repos=lalabuy948/PhoenixAnalytics&type=Timeline)](https://www.star-history.com/#lalabuy948/PhoenixAnalytics&Timeline)
