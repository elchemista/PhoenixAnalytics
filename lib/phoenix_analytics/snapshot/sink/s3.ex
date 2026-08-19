if Code.ensure_loaded?(ExAws.S3) do
  defmodule PhoenixAnalytics.Snapshot.Sink.S3 do
    @moduledoc """
    Sink writing snapshots to S3 compatible object storage.

    Only compiled when [ExAws](https://hex.pm/packages/ex_aws) is available. Add
    it to your application together with an S3 client stack:

        {:ex_aws, "~> 2.5"},
        {:ex_aws_s3, "~> 2.5"},
        {:req, "~> 0.5"},
        {:sweet_xml, "~> 0.7"}

    Credentials are resolved by ExAws as usual; per call overrides can be passed
    through the sink options.

    ## Options

      * `:bucket` - target bucket. Required.
      * `:region`, `:access_key_id`, `:secret_access_key`, `:host`, `:scheme`,
        `:port` - forwarded to `ExAws.request/2`, for non AWS endpoints too.

    ## Example

        config :phoenix_analytics,
          snapshot: [
            sink: {PhoenixAnalytics.Snapshot.Sink.S3, bucket: "my-analytics", region: "eu-west-1"},
            every: :day,
            at: ~T[03:00:00]
          ]
    """

    @behaviour PhoenixAnalytics.Snapshot.Sink

    @config_keys [:region, :access_key_id, :secret_access_key, :host, :scheme, :port]

    @impl PhoenixAnalytics.Snapshot.Sink
    def put(key, body, opts) do
      opts
      |> bucket!()
      |> ExAws.S3.put_object(key, IO.iodata_to_binary(body),
        content_type: "application/octet-stream"
      )
      |> ExAws.request(config(opts))
      |> to_result()
    end

    @impl PhoenixAnalytics.Snapshot.Sink
    def get(key, opts) do
      case opts |> bucket!() |> ExAws.S3.get_object(key) |> ExAws.request(config(opts)) do
        {:ok, %{body: body}} -> {:ok, body}
        {:error, reason} -> {:error, reason}
      end
    end

    @impl PhoenixAnalytics.Snapshot.Sink
    def list(prefix, opts) do
      keys =
        opts
        |> bucket!()
        |> ExAws.S3.list_objects_v2(prefix: prefix)
        |> ExAws.stream!(config(opts))
        |> Enum.map(& &1.key)

      {:ok, keys}
    rescue
      error -> {:error, error}
    end

    @impl PhoenixAnalytics.Snapshot.Sink
    def delete(key, opts) do
      opts
      |> bucket!()
      |> ExAws.S3.delete_object(key)
      |> ExAws.request(config(opts))
      |> to_result()
    end

    @spec bucket!(keyword()) :: String.t()
    defp bucket!(opts), do: Keyword.fetch!(opts, :bucket)

    @spec config(keyword()) :: keyword()
    defp config(opts), do: Keyword.take(opts, @config_keys)

    @spec to_result({:ok, term()} | {:error, term()}) :: :ok | {:error, term()}
    defp to_result({:ok, _response}), do: :ok
    defp to_result({:error, reason}), do: {:error, reason}
  end
end
