defmodule PhoenixAnalytics.Migration do
  @moduledoc false

  @doc """
  Creates the requests table using Ecto migrations.
  """
  def up do
    # Create the table using Ecto
    create_table_query = """
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
    );
    """

    repo = PhoenixAnalytics.Config.get_repo()

    case repo.query(create_table_query) do
      {:ok, _result} ->
        IO.puts("Migration applied: requests table created")
        {:ok, "Table created successfully"}

      {:error, reason} ->
        IO.puts("Failed to apply migration: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Drops the requests table.
  """
  def down do
    drop_table_query = "DROP TABLE IF EXISTS requests;"

    repo = PhoenixAnalytics.Config.get_repo()

    case repo.query(drop_table_query) do
      {:ok, _result} ->
        IO.puts("Migration rolled back: requests table dropped")
        {:ok, "Table dropped successfully"}

      {:error, reason} ->
        IO.puts("Failed to roll back migration: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Adds database indexes for optimal query performance.

  Creates indexes on frequently queried columns based on analytics usage patterns:
  - inserted_at for date range filtering
  - session_id for grouping operations
  - status_code for filtering and grouping
  - device_type for analytics aggregations
  - method for request type filtering
  - path for popular pages analysis

  Automatically detects database type and adjusts queries accordingly:
  - PostgreSQL/SQLite: Uses IF NOT EXISTS clause
  - MySQL: Omits IF NOT EXISTS, adds length limit to path index

  Note: Uses regular CREATE INDEX (not CONCURRENTLY) to work within migration transactions.
  For production environments with large tables, consider running PostgreSQL indexes manually with CONCURRENTLY.
  """
  def add_indexes do
    database_type = PhoenixAnalytics.Store.Ecto.database_type()
    database_name = database_type |> Atom.to_string() |> String.capitalize()
    statements = index_statements(database_type)

    repo = PhoenixAnalytics.Config.get_repo()

    {successful, failures} =
      statements
      |> Enum.map(&run_index(repo, &1))
      |> Enum.split_with(&match?({:ok, _statement}, &1))

    IO.puts(
      "#{database_name} indexes applied: #{length(successful)} successful, #{length(failures)} failed"
    )

    Enum.each(failures, &report_failure/1)

    {:ok,
     "#{database_name} indexes processed: #{length(successful)}/#{length(statements)} successful"}
  end

  # MySQL has no IF NOT EXISTS on CREATE INDEX and needs a prefix length on TEXT columns.
  @spec index_statements(:postgres | :sqlite | :mysql) :: [String.t()]
  defp index_statements(database_type) do
    {if_not_exists, path_column} = index_dialect(database_type)

    [
      "CREATE INDEX #{if_not_exists}idx_requests_inserted_at ON requests (inserted_at);",
      "CREATE INDEX #{if_not_exists}idx_requests_session_id ON requests (session_id);",
      "CREATE INDEX #{if_not_exists}idx_requests_status_code ON requests (status_code);",
      "CREATE INDEX #{if_not_exists}idx_requests_device_type ON requests (device_type);",
      "CREATE INDEX #{if_not_exists}idx_requests_method ON requests (method);",
      "CREATE INDEX #{if_not_exists}idx_requests_path ON requests (#{path_column});",
      "CREATE INDEX #{if_not_exists}idx_requests_date_status ON requests (inserted_at, status_code);",
      "CREATE INDEX #{if_not_exists}idx_requests_date_method ON requests (inserted_at, method);"
    ]
  end

  @spec index_dialect(:postgres | :sqlite | :mysql) :: {String.t(), String.t()}
  defp index_dialect(:mysql), do: {"", "path(255)"}
  defp index_dialect(_database_type), do: {"IF NOT EXISTS ", "path"}

  @spec run_index(module(), String.t()) :: {:ok, String.t()} | {:error, {String.t(), term()}}
  defp run_index(repo, statement) do
    case repo.query(statement) do
      {:ok, _result} -> {:ok, statement}
      {:error, reason} -> {:error, {statement, reason}}
    end
  end

  @spec report_failure({:error, {String.t(), term()}}) :: :ok
  defp report_failure({:error, {statement, reason}}) do
    IO.puts("Failed index: #{String.slice(statement, 0, 80)}... - #{failure_reason(reason)}")
  end

  @spec failure_reason(term()) :: String.t()
  defp failure_reason(%{postgres: %{message: message}}) when is_binary(message), do: message
  defp failure_reason(%{mysql: %{message: message}}) when is_binary(message), do: message
  defp failure_reason(%{message: message}) when is_binary(message), do: message
  defp failure_reason(reason), do: inspect(reason)
end
