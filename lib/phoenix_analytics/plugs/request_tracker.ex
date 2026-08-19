defmodule PhoenixAnalytics.Plugs.RequestTracker do
  @moduledoc """
  A Plug module for tracking and logging HTTP requests in a Phoenix application.

  It measures the duration of each request, keeps a lightweight session cookie,
  builds a validated `PhoenixAnalytics.Entities.RequestLog` and broadcasts it
  over PubSub, where `PhoenixAnalytics.Services.Batcher` picks it up.

  Add it to your endpoint right after the static plugs to start tracking:

      plug PhoenixAnalytics.Plugs.RequestTracker

  It also works inside a router pipeline, at the cost of not seeing static files:

      pipeline :browser do
        ...
        plug PhoenixAnalytics.Plugs.RequestTracker
      end

  Tracking never breaks a request: any error along the way is reported through
  telemetry and swallowed.

  ## Options

  Everything is optional; without options the plug behaves exactly as above.

      plug PhoenixAnalytics.Plugs.RequestTracker,
        before: [MyApp.Plugs.ConsentCheck, {MyApp.Plugs.BotFilter, min_score: 3}],
        after: [MyApp.Plugs.AnalyticsHeaders],
        filter: {MyApp.Analytics, :track?, []},
        transform: {MyApp.Analytics, :enrich, []},
        ignore_paths: ["/health", "/metrics", ~r{^/admin/}],
        session: [max_age: 300, same_site: "Lax"]

    * `:before` - plugs run before tracking starts. They can call
      `PhoenixAnalytics.Plugs.skip/1` to opt the request out, or `halt/1` to stop
      the whole endpoint pipeline as any plug would.
    * `:after` - plugs run once tracking is armed, with the session already set.
    * `:filter` - `{module, function, args}` receiving the connection and
      returning a boolean. A false result skips tracking entirely.
    * `:transform` - `{module, function, args}` receiving the request log and the
      connection, and returning an updated log or `nil` to drop it.
    * `:ignore_paths` - list of path prefixes or regexes never tracked.
    * `:session` - session cookie settings: `:cookie_name`,
      `:views_cookie_name`, `:max_age`, `:same_site`, `:secure`, `:http_only`.

  Callbacks are `{module, function, args}` tuples rather than anonymous
  functions because endpoints initialize plug options at compile time, where a
  closure cannot be built. `init/1` raises with a clear message if one is given.

  ## Order

      ignore_paths -> filter -> before plugs -> session -> response
        -> build -> transform -> broadcast -> after plugs

  ## Telemetry

    * `[:phoenix_analytics, :request, :tracked]` - measurements `%{duration_ms: ms}`,
      metadata `%{conn: conn, request_log: log}`.
    * `[:phoenix_analytics, :request, :skipped]` - metadata `%{conn: conn, reason: reason}`
      where reason is `:ignore_path`, `:filter`, `:before_plug` or `:transform`.
    * `[:phoenix_analytics, :error]` - any error raised while tracking.
  """

  @behaviour Plug

  import Plug.Conn

  alias PhoenixAnalytics.Entities.RequestLog
  alias PhoenixAnalytics.Plugs
  alias PhoenixAnalytics.Services.PubSub
  alias PhoenixAnalytics.Services.Telemetry
  alias PhoenixAnalytics.Services.Utility
  alias PhoenixAnalytics.Tracking.RequestLogBuilder

  @five_minutes 300

  @session_defaults [
    cookie_name: "pa_session_id",
    views_cookie_name: "pa_page_views",
    max_age: @five_minutes,
    same_site: "Lax",
    secure: false,
    http_only: true
  ]

  @cookie_keys [:max_age, :same_site, :secure, :http_only]

  # The page views cookie is client controlled: it is parsed defensively and
  # capped, so a malformed value cannot break the request and an oversized one
  # cannot overflow an integer column and fail the whole insert batch.
  @max_page_views 10_000

  @type options :: %{
          before: list(),
          after: list(),
          filter: mfa() | nil,
          transform: mfa() | nil,
          ignore_paths: [String.t() | Regex.t()],
          session: keyword()
        }

  @doc false
  @impl Plug
  def init(opts) do
    %{
      before: opts |> Keyword.get(:before, []) |> Enum.map(&init_plug!/1),
      after: opts |> Keyword.get(:after, []) |> Enum.map(&init_plug!/1),
      filter: opts |> Keyword.get(:filter) |> validate_mfa!(:filter),
      transform: opts |> Keyword.get(:transform) |> validate_mfa!(:transform),
      ignore_paths: opts |> Keyword.get(:ignore_paths, []) |> Enum.map(&validate_path!/1),
      session: Keyword.merge(@session_defaults, Keyword.get(opts, :session, []))
    }
  end

  @doc """
  Wraps the request, measures its duration and registers the tracking callback.

  Returns the connection, possibly carrying the session cookies and a
  `before_send` callback, and never raises.
  """
  @impl Plug
  def call(conn, opts) do
    started_at = System.monotonic_time(:millisecond)

    cond do
      ignored?(conn.request_path, opts.ignore_paths) -> skipped(conn, :ignore_path)
      not accepted?(opts.filter, conn) -> skipped(conn, :filter)
      true -> conn |> Plug.run(opts.before) |> track(opts, started_at)
    end
  end

  @spec track(Plug.Conn.t(), options(), integer()) :: Plug.Conn.t()
  defp track(%Plug.Conn{halted: true} = conn, _opts, _started_at), do: conn

  defp track(conn, opts, started_at) do
    if Plugs.skipped?(conn) do
      skipped(conn, :before_plug)
    else
      conn
      |> start_session(opts.session, started_at)
      |> register_before_send(&emit(&1, opts))
      |> Plug.run(opts.after)
    end
  end

  @spec start_session(Plug.Conn.t(), keyword(), integer()) :: Plug.Conn.t()
  defp start_session(conn, session, started_at) do
    conn = fetch_cookies(conn)
    cookie_name = Keyword.fetch!(session, :cookie_name)
    views_cookie_name = Keyword.fetch!(session, :views_cookie_name)

    session_id = conn.cookies[cookie_name] || Utility.uuid()
    page_views = next_page_views(conn.cookies[views_cookie_name])
    cookie_opts = Keyword.take(session, @cookie_keys)

    conn
    |> put_resp_cookie(cookie_name, session_id, cookie_opts)
    |> put_resp_cookie(views_cookie_name, Integer.to_string(page_views), cookie_opts)
    |> Plugs.update(
      &Map.merge(&1, %{session_id: session_id, page_views: page_views, started_at: started_at})
    )
  end

  @spec next_page_views(term()) :: pos_integer()
  defp next_page_views(cookie) when is_binary(cookie) do
    case Integer.parse(cookie) do
      {page_views, _rest} when page_views >= 0 -> min(page_views + 1, @max_page_views)
      _other -> 1
    end
  end

  defp next_page_views(_cookie), do: 1

  # Runs inside `before_send`: it must return the connection whatever happens.
  @spec emit(Plug.Conn.t(), options()) :: Plug.Conn.t()
  defp emit(conn, opts) do
    context = Map.fetch!(conn.private, Plugs.key())

    with {:ok, log} <- RequestLogBuilder.build(conn, context),
         {:ok, log} <- transform(opts.transform, log, conn) do
      PubSub.broadcast(log)

      :telemetry.execute(
        [:phoenix_analytics, :request, :tracked],
        %{duration_ms: log.duration_ms},
        %{conn: conn, request_log: log}
      )
    else
      :skip -> skipped(conn, :transform)
      {:error, reason} -> Telemetry.log_error(:invalid_request_log, reason)
    end

    conn
  rescue
    error ->
      Telemetry.log_error(:request_tracker, error)
      conn
  end

  @spec transform(mfa() | nil, RequestLog.t(), Plug.Conn.t()) :: {:ok, RequestLog.t()} | :skip
  defp transform(nil, log, _conn), do: {:ok, log}

  defp transform({module, function, args}, log, conn) do
    case apply(module, function, [log, conn | args]) do
      %RequestLog{} = log -> {:ok, log}
      nil -> :skip
    end
  end

  @spec accepted?(mfa() | nil, Plug.Conn.t()) :: boolean()
  defp accepted?(nil, _conn), do: true

  defp accepted?({module, function, args}, conn),
    do: apply(module, function, [conn | args]) == true

  @spec ignored?(String.t(), [String.t() | Regex.t()]) :: boolean()
  defp ignored?(path, patterns), do: Enum.any?(patterns, &matches?(&1, path))

  @spec matches?(String.t() | Regex.t(), String.t()) :: boolean()
  defp matches?(%Regex{} = pattern, path), do: Regex.match?(pattern, path)
  defp matches?(prefix, path) when is_binary(prefix), do: String.starts_with?(path, prefix)

  @spec skipped(Plug.Conn.t(), atom()) :: Plug.Conn.t()
  defp skipped(conn, reason) do
    :telemetry.execute([:phoenix_analytics, :request, :skipped], %{}, %{
      conn: conn,
      reason: reason
    })

    conn
  end

  @spec init_plug!(module() | {module(), term()} | (Plug.Conn.t() -> Plug.Conn.t())) ::
          {module(), term()} | (Plug.Conn.t() -> Plug.Conn.t())
  defp init_plug!(module) when is_atom(module), do: {module, module.init([])}
  defp init_plug!({module, opts}) when is_atom(module), do: {module, module.init(opts)}
  defp init_plug!(fun) when is_function(fun, 1), do: fun

  defp init_plug!(other) do
    raise ArgumentError, """
    invalid plug given to PhoenixAnalytics.Plugs.RequestTracker: #{inspect(other)}

    Expected a module, a {module, options} tuple or a function of arity one.
    """
  end

  @spec validate_mfa!(term(), atom()) :: mfa() | nil
  defp validate_mfa!(nil, _option), do: nil

  defp validate_mfa!({module, function, args} = mfa, _option)
       when is_atom(module) and is_atom(function) and is_list(args),
       do: mfa

  defp validate_mfa!(other, option) do
    raise ArgumentError, """
    invalid :#{option} given to PhoenixAnalytics.Plugs.RequestTracker: #{inspect(other)}

    Expected a {Module, :function, args} tuple. Plug options are built at compile
    time, so anonymous functions cannot be used here.
    """
  end

  @spec validate_path!(term()) :: String.t() | Regex.t()
  defp validate_path!(%Regex{} = pattern), do: pattern
  defp validate_path!(prefix) when is_binary(prefix), do: prefix

  defp validate_path!(other) do
    raise ArgumentError, """
    invalid :ignore_paths entry given to PhoenixAnalytics.Plugs.RequestTracker: #{inspect(other)}

    Expected a path prefix string or a regular expression.
    """
  end
end
