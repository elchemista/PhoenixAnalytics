defmodule PhoenixAnalytics.Snapshot.SchedulerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias PhoenixAnalytics.Snapshot.Scheduler
  alias PhoenixAnalytics.Snapshot.Sink.Local

  @moduletag :tmp_dir

  describe "schedule validation" do
    test "keeps the supported schedules", %{tmp_dir: tmp_dir} do
      for every <- [:manual, :day, {:hours, 6}, {:minutes, 15}] do
        assert state(tmp_dir, every: every).every == every
      end
    end

    test "an unusable :every falls back to a daily run instead of crashing", %{tmp_dir: tmp_dir} do
      # Left unvalidated these raise in init/1, and the supervisor restart loop
      # takes the whole host application down at boot.
      for every <- [0, "day", :daily, nil, {:hours, "6"}] do
        log = capture_log(fn -> assert state(tmp_dir, every: every).every == :day end)
        assert log =~ "ignoring invalid snapshot :every"
      end
    end

    test "a zero interval falls back too, instead of busy looping", %{tmp_dir: tmp_dir} do
      for every <- [{:hours, 0}, {:minutes, 0}, {:minutes, -5}] do
        assert capture_log(fn -> assert state(tmp_dir, every: every).every == :day end) =~
                 "ignoring invalid snapshot :every"
      end
    end

    test "an unusable :at falls back to the default time", %{tmp_dir: tmp_dir} do
      log = capture_log(fn -> assert state(tmp_dir, at: "03:00").at == ~T[03:00:00] end)

      assert log =~ "ignoring invalid snapshot :at"
    end

    test "a valid :at is kept", %{tmp_dir: tmp_dir} do
      assert state(tmp_dir, at: ~T[05:30:00]).at == ~T[05:30:00]
    end
  end

  # The scheduler registers under its module name, so each one is stopped before
  # the next is started.
  @spec state(String.t(), keyword()) :: map()
  defp state(tmp_dir, opts) do
    options = Keyword.merge([sink: {Local, path: tmp_dir}, every: :manual], opts)
    pid = start_supervised!({Scheduler, options}, restart: :temporary)
    state = :sys.get_state(pid)
    :ok = stop_supervised!(Scheduler)

    state
  end
end
