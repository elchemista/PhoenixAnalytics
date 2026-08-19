defmodule PhoenixAnalytics.Tracking.RequestLogBuilder do
  @moduledoc """
  Translates a `Plug.Conn` into a validated `PhoenixAnalytics.Entities.RequestLog`.

  This is the boundary between HTTP and the analytics domain: headers, cookies
  and connection internals stop here, and only a validated struct moves on. It
  needs nothing but a connection, so it can be tested with `Plug.Test` alone.
  """

  import Plug.Conn, only: [get_req_header: 2]

  alias PhoenixAnalytics.Entities.RequestLog
  alias PhoenixAnalytics.Services.Utility

  @typedoc "Tracking state carried by the connection between request and response."
  @type context :: %{
          required(:session_id) => String.t(),
          required(:page_views) => non_neg_integer(),
          required(:started_at) => integer(),
          optional(atom()) => term()
        }

  @ip_hash_range 1_000_000
  @unknown_user_agent "unknown"
  @direct_referer "Direct"
  @fallback_status 500

  @doc """
  Builds the request log of a finished request.

  Returns `{:error, changeset}` when the connection yields data the schema
  rejects, so the caller can drop it instead of storing something invalid.
  """
  @spec build(Plug.Conn.t(), context()) :: {:ok, RequestLog.t()} | {:error, Ecto.Changeset.t()}
  def build(conn, %{session_id: session_id, page_views: page_views, started_at: started_at}) do
    user_agent = header(conn, "user-agent", @unknown_user_agent)

    attrs = %{
      request_id: Utility.uuid(),
      method: conn.method,
      path: conn.request_path,
      status_code: conn.status || @fallback_status,
      duration_ms: System.monotonic_time(:millisecond) - started_at,
      user_agent: user_agent,
      remote_ip: conn |> remote_ip() |> hash_ip(),
      referer: header(conn, "referer", @direct_referer),
      device_type: Utility.get_device_type(user_agent),
      session_id: session_id,
      session_page_views: page_views,
      inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    }

    changeset = RequestLog.changeset(%RequestLog{}, attrs)

    if changeset.valid? do
      {:ok, Ecto.Changeset.apply_changes(changeset)}
    else
      {:error, changeset}
    end
  end

  # The address is hashed, never stored: visitors are counted, not identified.
  @spec hash_ip(String.t()) :: String.t()
  defp hash_ip(address), do: address |> :erlang.phash2(@ip_hash_range) |> Integer.to_string()

  @spec remote_ip(Plug.Conn.t()) :: String.t()
  defp remote_ip(%Plug.Conn{} = conn) do
    conn
    |> get_req_header("x-forwarded-for")
    |> List.first()
    |> forwarded_or_peer(conn)
    |> String.trim()
  end

  @spec forwarded_or_peer(String.t() | nil, Plug.Conn.t()) :: String.t()
  defp forwarded_or_peer(nil, conn) do
    case :inet.ntoa(conn.remote_ip) do
      {:error, _reason} -> ""
      address -> to_string(address)
    end
  end

  defp forwarded_or_peer(forwarded_for, _conn) do
    forwarded_for |> String.split(",", parts: 2) |> List.first()
  end

  @spec header(Plug.Conn.t(), String.t(), String.t()) :: String.t()
  defp header(conn, name, default) do
    conn |> get_req_header(name) |> List.first() || default
  end
end
