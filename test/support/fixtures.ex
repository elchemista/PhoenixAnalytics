defmodule PhoenixAnalytics.Fixtures do
  @moduledoc """
  Request logs shared by the store contract tests.

  The data set is deliberately small and hand checked, so every expected value
  in the contract can be derived by reading it.
  """

  alias PhoenixAnalytics.Entities.RequestLog

  @today ~N[2025-01-15 12:00:00]
  @today_later ~N[2025-01-15 12:00:30]
  @yesterday ~N[2025-01-14 12:00:00]
  @last_month ~N[2024-12-15 12:00:00]
  @last_year ~N[2024-01-15 12:00:00]

  @doc "Date of the most recent fixtures."
  @spec today() :: Date.t()
  def today, do: NaiveDateTime.to_date(@today)

  @doc "Date of the previous day fixtures."
  @spec yesterday() :: Date.t()
  def yesterday, do: NaiveDateTime.to_date(@yesterday)

  @doc "A date with no fixtures at all."
  @spec empty_day() :: Date.t()
  def empty_day, do: ~D[2025-01-01]

  @doc """
  Returns the fixture request logs.

  Three requests happen today across two sessions and two visitors, two
  yesterday in a single session, one last month and one last year.
  """
  @spec request_logs() :: [RequestLog.t()]
  def request_logs do
    [
      log("req_today_1", "GET", "/home", 200, 100,
        user_agent: "Mozilla/5.0",
        remote_ip: "192.168.1.1",
        referer: "https://google.com",
        device_type: "desktop",
        session_id: "session_1",
        session_page_views: 1,
        inserted_at: @today
      ),
      log("req_today_2", "GET", "/about", 200, 150,
        user_agent: "Mozilla/5.0",
        remote_ip: "192.168.1.1",
        referer: "https://google.com",
        device_type: "desktop",
        session_id: "session_1",
        session_page_views: 2,
        inserted_at: @today_later
      ),
      log("req_today_3", "GET", "/contact", 200, 120,
        user_agent: "Safari/605.1.15",
        remote_ip: "192.168.1.2",
        referer: "https://facebook.com",
        device_type: "mobile",
        session_id: "session_2",
        session_page_views: 1,
        inserted_at: @today
      ),
      log("req_yesterday_1", "GET", "/products", 200, 200,
        user_agent: "Chrome/91.0",
        remote_ip: "192.168.1.3",
        referer: "https://twitter.com",
        device_type: "desktop",
        session_id: "session_3",
        session_page_views: 1,
        inserted_at: @yesterday
      ),
      log("req_yesterday_2", "GET", "/services", 404, 50,
        user_agent: "Chrome/91.0",
        remote_ip: "192.168.1.3",
        referer: "https://twitter.com",
        device_type: "desktop",
        session_id: "session_3",
        session_page_views: 2,
        inserted_at: @yesterday
      ),
      log("req_last_month_1", "POST", "/api/users", 201, 300,
        user_agent: "curl/7.68.0",
        remote_ip: "192.168.1.4",
        referer: nil,
        device_type: "unknown",
        session_id: "session_4",
        session_page_views: 1,
        inserted_at: @last_month
      ),
      log("req_last_year_1", "GET", "/archive", 200, 80,
        user_agent: "Firefox/88.0",
        remote_ip: "192.168.1.5",
        referer: "https://github.com",
        device_type: "desktop",
        session_id: "session_5",
        session_page_views: 1,
        inserted_at: @last_year
      )
    ]
  end

  @spec log(String.t(), String.t(), String.t(), pos_integer(), non_neg_integer(), keyword()) ::
          RequestLog.t()
  defp log(request_id, method, path, status_code, duration_ms, attrs) do
    struct!(
      %RequestLog{
        request_id: request_id,
        method: method,
        path: path,
        status_code: status_code,
        duration_ms: duration_ms
      },
      attrs
    )
  end
end
