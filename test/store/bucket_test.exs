defmodule PhoenixAnalytics.Store.BucketTest do
  use ExUnit.Case, async: true

  alias PhoenixAnalytics.Store.Bucket

  describe "key/2" do
    test "labels a timestamp per interval" do
      timestamp = ~N[2025-01-15 13:24:56]

      assert Bucket.key(timestamp, :hour) == "2025-01-15 13:00:00"
      assert Bucket.key(timestamp, :day) == "2025-01-15"
      assert Bucket.key(timestamp, :month) == "2025-01"
      assert Bucket.key(timestamp, :year) == "2025"
    end
  end

  describe "normalize/2" do
    test "leaves database strings untouched" do
      assert Bucket.normalize("2025-01", :month) == "2025-01"
    end

    test "formats temporal structs like the SQL backends do" do
      assert Bucket.normalize(~D[2025-01-15], :day) == "2025-01-15"
      assert Bucket.normalize(~N[2025-01-15 13:00:00], :month) == "2025-01"
    end
  end
end
