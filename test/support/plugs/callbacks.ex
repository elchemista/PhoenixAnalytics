defmodule PhoenixAnalytics.TestPlugs.Callbacks do
  @moduledoc """
  Filter and transform callbacks used by the request tracker tests.
  """

  alias PhoenixAnalytics.Entities.RequestLog
  alias Plug.Conn

  @doc "Filter callback returning the value it was configured with."
  @spec track?(Conn.t(), boolean()) :: boolean()
  def track?(%Conn{}, allowed?), do: allowed?

  @doc "Transform callback tagging the log with the connection metadata."
  @spec tag(RequestLog.t(), Conn.t()) :: RequestLog.t()
  def tag(%RequestLog{} = log, %Conn{} = conn) do
    %{log | path: conn.request_path <> ":tagged"}
  end

  @doc "Transform callback dropping the log."
  @spec drop(RequestLog.t(), Conn.t()) :: nil
  def drop(%RequestLog{}, %Conn{}), do: nil
end
