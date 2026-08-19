defmodule PhoenixAnalytics.StoreTestRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :phoenix_analytics,
    adapter: Ecto.Adapters.SQLite3

  @doc "Creates the requests table used by the store contract tests."
  @spec create_requests_table!() :: :ok
  def create_requests_table! do
    query!("""
    CREATE TABLE IF NOT EXISTS requests (
      request_id VARCHAR(255) PRIMARY KEY,
      method VARCHAR(10) NOT NULL,
      path TEXT NOT NULL,
      status_code INTEGER NOT NULL,
      duration_ms INTEGER NOT NULL,
      user_agent TEXT,
      remote_ip VARCHAR(45),
      referer TEXT,
      device_type VARCHAR(20),
      session_id VARCHAR(255),
      session_page_views INTEGER,
      inserted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """)

    :ok
  end
end
