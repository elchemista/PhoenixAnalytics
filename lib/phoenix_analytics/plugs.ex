defmodule PhoenixAnalytics.Plugs do
  @moduledoc """
  Helpers for plugs running inside `PhoenixAnalytics.Plugs.RequestTracker`.

  Plugs listed under `:before` and `:after` receive the same connection the
  tracker works with, and can use these functions to opt a request out of
  tracking or to attach metadata a `:transform` callback will read later.

      defmodule MyApp.Plugs.ConsentCheck do
        @behaviour Plug

        import PhoenixAnalytics.Plugs

        @impl Plug
        def init(opts), do: opts

        @impl Plug
        def call(conn, _opts) do
          if consented?(conn), do: put_meta(conn, :plan, plan(conn)), else: skip(conn)
        end
      end
  """

  alias Plug.Conn

  @key :phoenix_analytics
  @empty %{meta: %{}}

  @doc """
  Marks the connection so the request is not tracked.

  Unlike `Plug.Conn.halt/1` this only stops the analytics tracking; the rest of
  the endpoint pipeline runs normally.
  """
  @spec skip(Conn.t()) :: Conn.t()
  def skip(conn), do: update(conn, &Map.put(&1, :skip, true))

  @doc "Returns true when the request was opted out of tracking."
  @spec skipped?(Conn.t()) :: boolean()
  def skipped?(conn), do: get_in(conn.private, [@key, :skip]) == true

  @doc "Attaches metadata readable from a `:transform` callback through `meta/1`."
  @spec put_meta(Conn.t(), atom(), term()) :: Conn.t()
  def put_meta(conn, key, value), do: update(conn, &put_in(&1, [:meta, key], value))

  @doc "Returns the metadata attached to the connection."
  @spec meta(Conn.t()) :: map()
  def meta(conn), do: get_in(conn.private, [@key, :meta]) || %{}

  @doc false
  @spec update(Conn.t(), (map() -> map())) :: Conn.t()
  def update(conn, fun) do
    Conn.put_private(conn, @key, fun.(Map.get(conn.private, @key, @empty)))
  end

  @doc false
  @spec key() :: atom()
  def key, do: @key
end
