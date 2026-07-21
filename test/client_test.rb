# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "scrapeunblocker"

class ClientTest < Minitest::Test
  def make_client(queue, **options)
    @urls = []
    @last_headers = {}
    transport = lambda do |url, headers|
      @urls << url
      @last_headers = headers
      queue.shift
    end
    ScrapeUnblocker::Client.new(api_key: "test-key", transport: transport, **options)
  end

  def test_raises_without_api_key
    ENV.delete("SCRAPEUNBLOCKER_KEY")
    assert_raises(ScrapeUnblocker::Error) { ScrapeUnblocker::Client.new }
  end

  def test_reads_api_key_from_env
    ENV["SCRAPEUNBLOCKER_KEY"] = "from-env"
    client = ScrapeUnblocker::Client.new(transport: ->(_u, _h) { { status: 200, body: "ok" } })
    assert_equal "ok", client.get_page_source("https://example.com")
  ensure
    ENV.delete("SCRAPEUNBLOCKER_KEY")
  end

  def test_get_page_source_returns_html
    client = make_client([{ status: 200, body: "<html>hi</html>" }])
    html = client.get_page_source("https://example.com", proxy_country: "US")

    assert_equal "<html>hi</html>", html
    assert_includes @urls[0], "/getPageSource"
    assert_includes @urls[0], "proxy_country=US"
    assert_equal "test-key", @last_headers["x-scrapeunblocker-key"]
  end

  def test_omits_nil_params
    client = make_client([{ status: 200, body: "ok" }])
    client.get_page_source("https://example.com")
    refute_includes @urls[0], "proxy_country"
    refute_includes @urls[0], "time_sleep"
  end

  def test_get_parsed_returns_parsed_page
    payload = { "data" => { "page_type" => "product", "source" => "schema.org", "data" => { "price" => 10 } } }
    client = make_client([{ status: 200, body: JSON.generate(payload) }])
    result = client.get_parsed("https://example.com/p/1", refresh_rules: true, rules_hint: "price missing")

    assert_instance_of ScrapeUnblocker::ParsedPage, result
    assert_equal "product", result.page_type
    assert_equal({ "price" => 10 }, result.data)
    assert_includes @urls[0], "parsed_data=true"
    assert_includes @urls[0], "refresh_rules=true"
  end

  def test_serp_targets_serpapi
    client = make_client([{ status: 200, body: JSON.generate("organic" => []) }])
    out = client.serp("hello world", pages_to_check: 2)

    assert_equal({ "organic" => [] }, out)
    assert_includes @urls[0], "/serpApi"
    assert_includes @urls[0], "pages_to_check=2"
  end

  def test_google_local_targets_maps_endpoint
    client = make_client([{ status: 200, body: JSON.generate("results" => []) }])
    out = client.google_local("coffee shops in chicago", proxy_country: "US", gl: "us")

    assert_equal({ "results" => [] }, out)
    assert_includes @urls[0], "/maps/google-local"
    assert_includes @urls[0], "keyword=coffee"
    assert_includes @urls[0], "proxy_country=US"
    assert_includes @urls[0], "gl=us"
  end

  def test_get_image_returns_bytes
    client = make_client([{ status: 200, body: "\x89PNG" }])
    assert_equal "\x89PNG", client.get_image("https://example.com/x.png")
  end

  def test_skyscanner_flights
    client = make_client([{ status: 200, body: JSON.generate("itineraries" => []) }])
    out = client.skyscanner.flights(origin: "London", dest: "Paris")

    assert_equal({ "itineraries" => [] }, out)
    assert_includes @urls[0], "/flights/skyscanner-quotes"
    assert_includes @urls[0], "origin=London"
  end

  def test_error_mapping
    {
      400 => ScrapeUnblocker::InvalidRequestError,
      403 => ScrapeUnblocker::BlockedError,
      429 => ScrapeUnblocker::RateLimitError,
      503 => ScrapeUnblocker::UpstreamOutageError
    }.each do |status, klass|
      client = make_client([{ status: status, body: "nope" }], max_retries: 0)
      err = assert_raises(klass) { client.get_page_source("https://example.com") }
      assert_equal status, err.status_code
    end
  end

  def test_retries_then_succeeds
    client = make_client(
      [{ status: 503, body: "outage" }, { status: 200, body: "recovered" }],
      max_retries: 2
    )
    assert_equal "recovered", client.get_page_source("https://example.com")
    assert_equal 2, @urls.length
  end
end
