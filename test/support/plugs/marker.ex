defmodule PhoenixAnalytics.TestPlugs.Marker do
  @moduledoc """
  Test plug recording that it ran, and optionally acting on the connection.

  ## Options

    * `:tag` - value appended to `conn.assigns.marks`. Required.
    * `:action` - `:none` (default), `:halt` or `:skip`.
  """

  @behaviour Plug

  alias PhoenixAnalytics.Plugs
  alias Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    conn
    |> Conn.assign(:marks, Map.get(conn.assigns, :marks, []) ++ [Keyword.fetch!(opts, :tag)])
    |> act(Keyword.get(opts, :action, :none))
  end

  @spec act(Conn.t(), :none | :halt | :skip) :: Conn.t()
  defp act(conn, :none), do: conn
  defp act(conn, :halt), do: Conn.halt(conn)
  defp act(conn, :skip), do: Plugs.skip(conn)
end
