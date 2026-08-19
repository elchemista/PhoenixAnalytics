defmodule PhoenixAnalytics.FiltersTest do
  use ExUnit.Case, async: true

  alias PhoenixAnalytics.Filters

  describe "static_asset?/1" do
    test "matches known asset extensions" do
      assert Filters.static_asset?("/app.js")
      assert Filters.static_asset?("/images/logo.png")
      refute Filters.static_asset?("/home")
      refute Filters.static_asset?("/jsonapi")
    end
  end

  describe "asset_path?/1" do
    test "matches asset directories anywhere in the path" do
      assert Filters.asset_path?("/assets/app-1234")
      assert Filters.asset_path?("/nested/uploads/file")
      refute Filters.asset_path?("/home")
    end
  end

  describe "dev_path?/1" do
    test "matches development only paths" do
      assert Filters.dev_path?("/phoenix/live_reload/socket")
      assert Filters.dev_path?("/dev/dashboard")
      refute Filters.dev_path?("/developers")
    end
  end

  describe "page_path?/1" do
    test "excludes assets but keeps pages" do
      assert Filters.page_path?("/home")
      refute Filters.page_path?("/app.css")
      refute Filters.page_path?("/assets/app.txt")
    end
  end

  describe "pageview?/1" do
    test "counts only successful GET requests to pages" do
      assert Filters.pageview?(%{method: "GET", status_code: 200, path: "/home"})
      refute Filters.pageview?(%{method: "POST", status_code: 200, path: "/home"})
      refute Filters.pageview?(%{method: "GET", status_code: 404, path: "/home"})
      refute Filters.pageview?(%{method: "GET", status_code: 200, path: "/app.js"})
    end
  end

  describe "external_referer?/2" do
    test "keeps only referrers outside the application domain" do
      assert Filters.external_referer?("https://google.com", "example.com")
      refute Filters.external_referer?("https://example.com/page", "example.com")
      refute Filters.external_referer?("unknown", "example.com")
      refute Filters.external_referer?(nil, "example.com")
    end
  end

  describe "resource_path?/1" do
    test "matches asset like requests" do
      assert Filters.resource_path?("/assets/app.js")
      assert Filters.resource_path?("favicon")
      refute Filters.resource_path?("/home/about")
    end
  end
end
