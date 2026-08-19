defmodule PhoenixAnalytics.Plugs.RequestTrackerTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias PhoenixAnalytics.Entities.RequestLog
  alias PhoenixAnalytics.Plugs.RequestTracker
  alias PhoenixAnalytics.Services.PubSub
  alias PhoenixAnalytics.TestPlugs.Callbacks
  alias PhoenixAnalytics.TestPlugs.Marker
  alias Plug.Conn

  setup do
    PubSub.subscribe()
    :ok
  end

  describe "without options" do
    test "tracks the request and sets the session cookies" do
      conn = request("/home")

      assert_receive {:request_sent, %RequestLog{} = log}
      assert log.path == "/home"
      assert log.method == "GET"
      assert log.status_code == 200
      assert log.session_page_views == 1
      assert log.duration_ms >= 0

      cookies = resp_cookies(conn)
      assert cookies["pa_page_views"].value == "1"
      assert cookies["pa_session_id"].value == log.session_id
      assert cookies["pa_session_id"].max_age == 300
    end

    test "keeps the session and counts page views across requests" do
      first = request("/home")
      session_id = resp_cookies(first)["pa_session_id"].value
      assert_receive {:request_sent, %RequestLog{}}

      second =
        request("/about", cookies: %{"pa_session_id" => session_id, "pa_page_views" => "1"})

      assert_receive {:request_sent, %RequestLog{} = log}
      assert log.session_id == session_id
      assert log.session_page_views == 2
      assert resp_cookies(second)["pa_page_views"].value == "2"
    end

    test "hashes the remote address" do
      request("/home")

      assert_receive {:request_sent, %RequestLog{remote_ip: remote_ip}}
      assert remote_ip == Integer.to_string(:erlang.phash2("127.0.0.1", 1_000_000))
    end

    test "emits a tracked telemetry event" do
      attach_telemetry([:phoenix_analytics, :request, :tracked])
      request("/home")

      assert_receive {:telemetry, [:phoenix_analytics, :request, :tracked], measurements,
                      metadata}

      assert is_integer(measurements.duration_ms)
      assert %RequestLog{path: "/home"} = metadata.request_log
    end
  end

  describe ":before and :after plugs" do
    test "run around the tracking, in order" do
      conn =
        request("/home",
          before: [{Marker, tag: :first}, {Marker, tag: :second}],
          after: [{Marker, tag: :third}]
        )

      assert conn.assigns.marks == [:first, :second, :third]
      assert_receive {:request_sent, %RequestLog{}}
    end

    test "a halted before plug stops the pipeline and the tracking" do
      conn =
        request("/home",
          before: [{Marker, tag: :first, action: :halt}],
          after: [{Marker, tag: :second}]
        )

      assert conn.halted
      assert conn.assigns.marks == [:first]
      assert resp_cookies(conn) == %{}
      refute_receive {:request_sent, _log}
    end

    test "a before plug can skip tracking without halting" do
      attach_telemetry([:phoenix_analytics, :request, :skipped])
      conn = request("/home", before: [{Marker, tag: :first, action: :skip}])

      assert resp_cookies(conn) == %{}
      refute conn.halted
      refute_receive {:request_sent, _log}
      assert_receive {:telemetry, _event, _measurements, %{reason: :before_plug}}
    end
  end

  describe ":filter" do
    test "skips the request when the callback returns false" do
      attach_telemetry([:phoenix_analytics, :request, :skipped])
      conn = request("/home", filter: {Callbacks, :track?, [false]})

      assert resp_cookies(conn) == %{}
      refute_receive {:request_sent, _log}
      assert_receive {:telemetry, _event, _measurements, %{reason: :filter}}
    end

    test "tracks the request when the callback returns true" do
      request("/home", filter: {Callbacks, :track?, [true]})

      assert_receive {:request_sent, %RequestLog{}}
    end
  end

  describe ":ignore_paths" do
    test "skips path prefixes and regexes" do
      attach_telemetry([:phoenix_analytics, :request, :skipped])

      assert resp_cookies(request("/health", ignore_paths: ["/health"])) == %{}
      assert_receive {:telemetry, _event, _measurements, %{reason: :ignore_path}}

      assert resp_cookies(request("/admin/users", ignore_paths: [~r{^/admin/}])) == %{}
      refute_receive {:request_sent, _log}
    end

    test "keeps tracking the other paths" do
      request("/home", ignore_paths: ["/health"])

      assert_receive {:request_sent, %RequestLog{path: "/home"}}
    end
  end

  describe ":transform" do
    test "replaces the log with the returned one" do
      request("/home", transform: {Callbacks, :tag, []})

      assert_receive {:request_sent, %RequestLog{path: "/home:tagged"}}
    end

    test "drops the log when the callback returns nil" do
      attach_telemetry([:phoenix_analytics, :request, :skipped])
      request("/home", transform: {Callbacks, :drop, []})

      refute_receive {:request_sent, _log}
      assert_receive {:telemetry, _event, _measurements, %{reason: :transform}}
    end
  end

  describe ":session" do
    test "uses the configured cookie names and lifetime" do
      conn =
        request("/home", session: [cookie_name: "sid", views_cookie_name: "views", max_age: 60])

      cookies = resp_cookies(conn)
      assert Map.has_key?(cookies, "sid")
      assert cookies["views"].value == "1"
      assert cookies["sid"].max_age == 60
      refute Map.has_key?(cookies, "pa_session_id")
    end
  end

  describe "init/1" do
    test "rejects anonymous functions in callbacks" do
      assert_raise ArgumentError, ~r/anonymous functions cannot be used/, fn ->
        RequestTracker.init(filter: fn _conn -> true end)
      end

      assert_raise ArgumentError, ~r/anonymous functions cannot be used/, fn ->
        RequestTracker.init(transform: fn _log, _conn -> nil end)
      end
    end

    test "rejects invalid plugs and ignore paths" do
      assert_raise ArgumentError, ~r/invalid plug/, fn ->
        RequestTracker.init(before: ["not a plug"])
      end

      assert_raise ArgumentError, ~r/invalid :ignore_paths/, fn ->
        RequestTracker.init(ignore_paths: [:home])
      end
    end
  end

  @spec request(String.t(), keyword()) :: Conn.t()
  defp request(path, opts \\ []) do
    {cookies, opts} = Keyword.pop(opts, :cookies, %{})

    :get
    |> conn(path)
    |> put_req_cookies(cookies)
    |> RequestTracker.call(RequestTracker.init(opts))
    |> Conn.send_resp(200, "ok")
  end

  @spec put_req_cookies(Conn.t(), map()) :: Conn.t()
  defp put_req_cookies(conn, cookies) when map_size(cookies) == 0, do: conn

  defp put_req_cookies(conn, cookies) do
    header = Enum.map_join(cookies, "; ", fn {name, value} -> "#{name}=#{value}" end)

    Conn.put_req_header(conn, "cookie", header)
  end

  @spec resp_cookies(Conn.t()) :: map()
  defp resp_cookies(conn), do: conn.resp_cookies

  @spec attach_telemetry([atom()]) :: :ok
  defp attach_telemetry(event) do
    handler_id = {__MODULE__, event, self()}
    test_process = self()

    :telemetry.attach(
      handler_id,
      event,
      fn name, measurements, metadata, _config ->
        send(test_process, {:telemetry, name, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
