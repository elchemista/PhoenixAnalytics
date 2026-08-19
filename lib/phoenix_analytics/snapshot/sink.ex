defmodule PhoenixAnalytics.Snapshot.Sink do
  @moduledoc """
  Destination of a snapshot.

  A sink is a plain key/value blob store. `PhoenixAnalytics.Snapshot.Sink.Local`
  writes to the filesystem and `PhoenixAnalytics.Snapshot.Sink.S3` to object
  storage; anything else that can put, get, list and delete a key works too.
  """

  @type opts :: keyword()

  @doc "Writes a snapshot under the given key."
  @callback put(key :: String.t(), body :: iodata(), opts()) :: :ok | {:error, term()}

  @doc "Reads back the snapshot stored under the given key."
  @callback get(key :: String.t(), opts()) :: {:ok, binary()} | {:error, term()}

  @doc "Lists every key starting with the given prefix."
  @callback list(prefix :: String.t(), opts()) :: {:ok, [String.t()]} | {:error, term()}

  @doc "Removes the snapshot stored under the given key."
  @callback delete(key :: String.t(), opts()) :: :ok | {:error, term()}
end
