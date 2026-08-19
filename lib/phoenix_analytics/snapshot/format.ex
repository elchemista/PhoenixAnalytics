defmodule PhoenixAnalytics.Snapshot.Format do
  @moduledoc """
  Serialization of request logs inside a snapshot.

  Two formats are supported:

    * `:etf` - Erlang term format, compact and lossless. The default, and the
      one to use when snapshots are meant to be restored.
    * `:jsonl` - one JSON object per line, for snapshots meant to be read by
      external tools such as Athena, DuckDB or BigQuery.
  """

  alias PhoenixAnalytics.Entities.RequestLog

  @type format :: :etf | :jsonl

  @fields ~w(request_id method path status_code duration_ms user_agent remote_ip
             referer device_type session_id session_page_views inserted_at)a

  @doc """
  Encodes request logs into the snapshot body.

  ## Examples

      iex> logs = [%PhoenixAnalytics.Entities.RequestLog{request_id: "a", inserted_at: ~N[2025-01-15 12:00:00]}]
      iex> body = PhoenixAnalytics.Snapshot.Format.encode(logs, :jsonl)
      iex> body |> IO.iodata_to_binary() |> String.contains?(~s("request_id":"a"))
      true
  """
  @spec encode([RequestLog.t()], format()) :: iodata()
  def encode(logs, :etf) do
    logs |> Enum.map(&to_map/1) |> :erlang.term_to_binary([:compressed])
  end

  def encode(logs, :jsonl) do
    Enum.map(logs, &[&1 |> to_map() |> json_encode!(), ?\n])
  end

  @doc """
  Decodes a snapshot body back into request logs.

  ## Examples

      iex> logs = [%PhoenixAnalytics.Entities.RequestLog{request_id: "a", method: "GET", path: "/", status_code: 200, duration_ms: 1, inserted_at: ~N[2025-01-15 12:00:00]}]
      iex> logs |> PhoenixAnalytics.Snapshot.Format.encode(:etf) |> PhoenixAnalytics.Snapshot.Format.decode(:etf) |> hd() |> Map.get(:request_id)
      "a"
  """
  @spec decode(binary(), format()) :: [RequestLog.t()]
  def decode(body, :etf) do
    # `:safe` keeps a corrupted or foreign snapshot from creating new atoms.
    body |> :erlang.binary_to_term([:safe]) |> Enum.map(&to_log!/1)
  end

  def decode(body, :jsonl) do
    body
    |> String.split("\n", trim: true)
    |> Enum.map(&(&1 |> json_decode!() |> to_log!()))
  end

  @doc """
  Returns the file extension of a snapshot body.

  ## Examples

      iex> PhoenixAnalytics.Snapshot.Format.extension(:etf, true)
      "etf.gz"
  """
  @spec extension(format(), boolean()) :: String.t()
  def extension(format, false), do: to_string(format)
  def extension(format, true), do: "#{format}.gz"

  @spec to_map(RequestLog.t()) :: map()
  defp to_map(%RequestLog{} = log) do
    log
    |> Map.from_struct()
    |> Map.take(@fields)
    |> Map.update!(:inserted_at, &encode_timestamp/1)
  end

  @spec encode_timestamp(NaiveDateTime.t() | nil) :: String.t() | nil
  defp encode_timestamp(nil), do: nil
  defp encode_timestamp(%NaiveDateTime{} = timestamp), do: NaiveDateTime.to_iso8601(timestamp)

  @spec to_log!(map()) :: RequestLog.t()
  defp to_log!(attrs) do
    %RequestLog{}
    |> RequestLog.changeset(attrs)
    |> Ecto.Changeset.apply_action!(:insert)
  end

  if Code.ensure_loaded?(JSON) do
    @spec json_encode!(map()) :: iodata()
    defp json_encode!(map), do: JSON.encode!(map)

    @spec json_decode!(String.t()) :: map()
    defp json_decode!(line), do: JSON.decode!(line)
  else
    @spec json_encode!(map()) :: iodata()
    defp json_encode!(map), do: Jason.encode!(map)

    @spec json_decode!(String.t()) :: map()
    defp json_decode!(line), do: Jason.decode!(line)
  end
end
