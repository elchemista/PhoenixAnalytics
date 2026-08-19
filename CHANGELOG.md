# Changelog

All notable changes to this project will be documented in this file.

## [0.5.0]

### ✨ New Features

- **Pluggable stores**: storage now sits behind the `PhoenixAnalytics.Store`
  behaviour. Configure it with `store: {Module, opts}`, or keep using `repo:`
  which selects the Ecto store automatically.
- **ETS store**: `PhoenixAnalytics.Store.ETS` keeps analytics in node memory,
  with retention by age (`:retention_days`) and by size (`:max_entries`), and
  needs no database or migration.
- **Snapshots**: `PhoenixAnalytics.Snapshot` exports a period to a sink on a
  schedule and restores it at boot. Ships with a local filesystem sink and an S3
  sink (optional ExAws dependency), in `:etf` or `:jsonl` format.
- **Extensible tracking plug**: `PhoenixAnalytics.Plugs.RequestTracker` accepts
  `:before` and `:after` plugs, `:filter`, `:transform`, `:ignore_paths` and
  `:session` options, plus `PhoenixAnalytics.Plugs.skip/1` and `put_meta/3` for
  custom plugs.
- **Telemetry**: new `[:phoenix_analytics, :request, :tracked]` and
  `[:phoenix_analytics, :request, :skipped]` events, and
  `[:phoenix_analytics, :snapshot, :start | :stop | :exception]`.
- **Batcher configuration**: `batcher: [batch_size: 100, flush_interval_ms: 1_000]`.

### 🐛 Bug Fixes

- Stat card sparklines were always empty: the dashboard matched query results as
  lists while they are maps.
- Period labels are now consistent across backends. PostgreSQL returned
  `Date`/`NaiveDateTime` structs where SQLite and MySQL returned strings.
- Failed dashboard reads are no longer cached, so the next render retries
  instead of showing the fallback until the TTL expires.
- `:cache_ttl` is now read at runtime instead of at compile time, so it can be
  set from `config/runtime.exs`, and a string value such as
  `System.get_env("CACHE_TTL")` no longer crashes on every cache write.
- A malformed `pa_page_views` cookie made every request fail with a 500. The
  cookie is client controlled, so any visitor could take a page down by setting
  it; it is now parsed defensively.
- An oversized `pa_page_views` cookie reached the database as a bignum and made
  the whole insert batch fail, discarding up to `batch_size` unrelated requests
  with it. Page views are now capped.
- A cache outage made the dashboard render Cachex's error reason, such as
  `:no_cache`, in place of the chart data.
- The batcher dropped its pending batch on shutdown, losing up to `batch_size`
  requests on every restart or deploy. It now flushes on terminate.
- An unparseable date range or interval coming from the dashboard client left
  every chart silently empty; both are now validated and the current value kept.
- A malformed `:every` or `:at` in the snapshot configuration crashed the
  scheduler in a restart loop, which took the host application down at boot; a
  zero interval busy looped writing snapshots. Both now warn and fall back.
- `PhoenixAnalytics.Store.ETS.info/1` reported timestamps with millisecond
  precision while every stored `inserted_at` has second precision.

### 🔧 Improvements

- Dashboard reads go through a single `PhoenixAnalytics.Web.Data` module instead
  of the same cache, query and error handling code repeated in seven components.
- Request classification rules live in `PhoenixAnalytics.Filters` and are shared
  by every store, so all backends agree on what a pageview is.
- Request log construction moved to `PhoenixAnalytics.Tracking.RequestLogBuilder`.

### ⚠️ Behaviour notes

- `PhoenixAnalytics.Config.get_cache_ttl/0` is now the single source of the
  cache TTL and its default is `120` seconds, the value the cache used before.
- `c:PhoenixAnalytics.Store.import_all/2` returns how many logs were imported,
  counting those already stored, so every adapter reports the same number on a
  replay. The Ecto store previously returned only the newly inserted rows.

### ⚠️ Deprecations

- `PhoenixAnalytics.Services.Utility.database_type/0` and `mode/0`: use
  `PhoenixAnalytics.Store.Ecto.database_type/0`.

### 🧹 Removals

- `PhoenixAnalytics.Queries.Insert` and `PhoenixAnalytics.Queries.Table`, which
  were unused.

> No breaking changes: an existing `repo:` configuration and a bare
> `plug PhoenixAnalytics.Plugs.RequestTracker` behave exactly as in 0.4.

---

## [0.4.0] - 14-08-2025

### 🚨 BREAKING CHANGES

- **Removed Duck Feature**: The 🦆 duck emoji branding has been completely removed from the UI and codebase
- **Migration Path**: Users who prefer the duck-themed version should use the maintained fork at [https://github.com/lalabuy948/PhoenixAnalyticsDuck](https://github.com/lalabuy948/PhoenixAnalyticsDuck)

### ✨ New Features

- **Pure plug and play**: Sqlite, Postgres and MySQL support out of the box using your repo!
- **Color Theme System**: Added 12 color themes (Zinc, Slate, Stone, Gray, Neutral, Red, Rose, Orange, Green, Blue, Yellow, Violet)

### 🔧 Improvements

- **Database Indexes**: Added optional `add_indexes()` function for optimized query performance
- **Multi-Database Support**: Unified index creation for PostgreSQL, MySQL, and SQLite
- **CSS Architecture**: Comprehensive CSS custom properties system for theme management
- **Dark Mode Compatibility**: All color themes work seamlessly in both light and dark modes

---

> [!NOTE]
> For detailed release notes, please check the [GitHub releases page](https://github.com/lalabuy948/PhoenixAnalytics/releases).
