defmodule PhoenixAnalytics.Snapshot.Sink.Local do
  @moduledoc """
  Sink writing snapshots to the local filesystem.

  Useful in development and tests, and in production for hosts that already
  back up a mounted volume.

  ## Options

    * `:path` - root directory holding the snapshots. Required.

  ## Example

      config :phoenix_analytics,
        snapshot: [sink: {PhoenixAnalytics.Snapshot.Sink.Local, path: "tmp/snapshots"}]
  """

  @behaviour PhoenixAnalytics.Snapshot.Sink

  @impl PhoenixAnalytics.Snapshot.Sink
  def put(key, body, opts) do
    path = Path.join(root!(opts), key)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, body)
    end
  end

  @impl PhoenixAnalytics.Snapshot.Sink
  def get(key, opts), do: File.read(Path.join(root!(opts), key))

  @impl PhoenixAnalytics.Snapshot.Sink
  def list(prefix, opts) do
    root = root!(opts)

    keys =
      root
      |> Path.join(prefix <> "**")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&Path.relative_to(&1, root))

    {:ok, keys}
  end

  @impl PhoenixAnalytics.Snapshot.Sink
  def delete(key, opts), do: File.rm(Path.join(root!(opts), key))

  @spec root!(keyword()) :: String.t()
  defp root!(opts), do: Keyword.fetch!(opts, :path)
end
