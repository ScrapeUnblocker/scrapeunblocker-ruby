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

  def test_get_page_source_encodes_steps_as_json_query_param
    client = make_client([{ status: 200, body: "<html>done</html>" }])
    steps = [
      { "action" => "wait_for", "selector" => "#results" },
      { "action" => "type", "selector" => "input#q", "value" => "hello", "clear" => true },
      { "action" => "press_key", "value" => "Enter" }
    ]
    html = client.get_page_source("https://example.com", steps: steps)

    assert_equal "<html>done</html>", html
    query = URI.parse(@urls[0]).query
    steps_param = URI.decode_www_form(query).to_h["steps"]
    assert_equal steps, JSON.parse(steps_param)
  end

  def test_get_page_source_omits_steps_when_absent
    client = make_client([{ status: 200, body: "ok" }])
    client.get_page_source("https://example.com")
    refute_includes @urls[0], "steps="
    refute_includes @urls[0], "list_elements"
  end

  def test_get_page_source_list_elements_returns_parsed_json
    payload = { "url" => "https://example.com", "count" => 2,
                "elements" => [{ "text" => "a" }, { "text" => "b" }] }
    client = make_client([{ status: 200, body: JSON.generate(payload) }])
    out = client.get_page_source("https://example.com", list_elements: true)

    assert_equal payload, out
    assert_includes @urls[0], "list_elements=true"
  end

  def test_get_page_source_surfaces_step_failed_422
    body = JSON.generate("error" => "step_failed", "step_index" => 0,
                         "action" => "wait_for", "reason" => "timeout",
                         "selector" => "#missing", "html" => "<html></html>")
    client = make_client([{ status: 422, body: body }], max_retries: 0)
    err = assert_raises(ScrapeUnblocker::ValidationError) do
      client.get_page_source("https://example.com",
                             steps: [{ "action" => "wait_for", "selector" => "#missing" }])
    end
    assert_equal 422, err.status_code
    assert_equal body, err.body
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

  def test_google_images_targets_images_endpoint
    client = make_client([{ status: 200, body: JSON.generate("results" => []) }])
    out = client.google_images("golden retriever puppy", proxy_country: "US", gl: "us")

    assert_equal({ "results" => [] }, out)
    assert_includes @urls[0], "/images/google-search"
    assert_includes @urls[0], "q=golden"
    assert_includes @urls[0], "proxy_country=US"
    assert_includes @urls[0], "gl=us"
    # Unset optional params must not be sent at all.
    refute_includes @urls[0], "max_results="
  end

  def test_meta_ad_library_targets_ads_endpoint
    client = make_client([{ status: 200, body: JSON.generate("results" => []) }])
    out = client.meta_ad_library("Nike", country: "US")

    assert_equal({ "results" => [] }, out)
    assert_includes @urls[0], "/ads/meta-ad-library"
    assert_includes @urls[0], "advertiser=Nike"
    assert_includes @urls[0], "country=US"
    # Unset optional filters must not be sent at all.
    refute_includes @urls[0], "active_status="
    refute_includes @urls[0], "max_ads="
  end

  def test_oopbuy_search_targets_goods_endpoint
    client = make_client([{ status: 200, body: JSON.generate("results" => []) }])
    out = client.oopbuy_search("running shoes", channel: "taobao", proxy_country: "US")

    assert_equal({ "results" => [] }, out)
    assert_includes @urls[0], "/goods/oopbuy-search"
    assert_includes @urls[0], "keyword=running"
    assert_includes @urls[0], "channel=taobao"
    assert_includes @urls[0], "page=1"
    assert_includes @urls[0], "page_size=20"
    assert_includes @urls[0], "sort=default"
    assert_includes @urls[0], "proxy_country=US"
  end

  def test_ebay_search_targets_marketplace_endpoint
    client = make_client([{ status: 200, body: JSON.generate("results" => [], "exactMatches" => true) }])
    out = client.ebay_search("iphone 13", marketplace: "ebay.de", condition: "used",
                                          sort: "newly_listed", min_price: 100, max_price: 300)

    assert_equal({ "results" => [], "exactMatches" => true }, out)
    assert_includes @urls[0], "/marketplace/ebay-search"
    assert_includes @urls[0], "keyword=iphone"
    assert_includes @urls[0], "marketplace=ebay.de"
    assert_includes @urls[0], "condition=used"
    assert_includes @urls[0], "sort=newly_listed"
    assert_includes @urls[0], "min_price=100"
    assert_includes @urls[0], "max_price=300"
    assert_includes @urls[0], "page_size=60"
    # Unset optional filters must not be sent at all.
    refute_includes @urls[0], "seller="
    refute_includes @urls[0], "free_shipping="
  end

  def test_amazon_product_targets_marketplace_endpoint
    client = make_client([{ status: 200, body: JSON.generate("asin" => "B0BSHF7WHW", "price" => 49.99) }])
    out = client.amazon_product(asin: "B0BSHF7WHW", marketplace: "amazon.com")

    assert_equal({ "asin" => "B0BSHF7WHW", "price" => 49.99 }, out)
    assert_includes @urls[0], "/marketplace/amazon-product"
    assert_includes @urls[0], "asin=B0BSHF7WHW"
    assert_includes @urls[0], "marketplace=amazon.com"
    # Unset optional params must not be sent at all.
    refute_includes @urls[0], "url="
    refute_includes @urls[0], "proxy_country="
  end

  def test_amazon_search_targets_marketplace_endpoint
    client = make_client([{ status: 200, body: JSON.generate("results" => [], "resultsCollected" => 0) }])
    out = client.amazon_search("wireless headphones", marketplace: "amazon.de",
                                                       sort: "price_asc", min_price: 50, max_price: 200)

    assert_equal({ "results" => [], "resultsCollected" => 0 }, out)
    assert_includes @urls[0], "/marketplace/amazon-search"
    assert_includes @urls[0], "keyword=wireless"
    assert_includes @urls[0], "marketplace=amazon.de"
    assert_includes @urls[0], "sort=price_asc"
    assert_includes @urls[0], "min_price=50"
    assert_includes @urls[0], "max_price=200"
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

  def test_southwest_flights
    client = make_client([{ status: 200, body: JSON.generate("itineraries" => []) }])
    out = client.southwest.flights(origin: "DAL", dest: "HOU", depart_date: "2026-10-20",
                                   return_date: "2026-10-27", adults: 2, fare_type: "points")

    assert_equal({ "itineraries" => [] }, out)
    assert_includes @urls[0], "/flights/southwest-quotes"
    assert_includes @urls[0], "origin=DAL"
    assert_includes @urls[0], "dest=HOU"
    assert_includes @urls[0], "depart_date=2026-10-20"
    assert_includes @urls[0], "return_date=2026-10-27"
    assert_includes @urls[0], "adults=2"
    assert_includes @urls[0], "fare_type=points"
    assert_includes @urls[0], "proxy_country=US"
    assert_includes @urls[0], "max_attempts=3"
  end

  def test_southwest_flights_omits_return_date_for_one_way
    client = make_client([{ status: 200, body: JSON.generate("itineraries" => []) }])
    client.southwest.flights(origin: "DAL", dest: "HOU", depart_date: "2026-10-20")

    assert_includes @urls[0], "/flights/southwest-quotes"
    assert_includes @urls[0], "fare_type=dollars"
    refute_includes @urls[0], "return_date="
  end

  def test_error_mapping
    {
      400 => ScrapeUnblocker::InvalidRequestError,
      401 => ScrapeUnblocker::AuthenticationError,
      402 => ScrapeUnblocker::PaymentRequiredError,
      403 => ScrapeUnblocker::BlockedError,
      404 => ScrapeUnblocker::NotFoundError,
      408 => ScrapeUnblocker::BrowserTimeoutError,
      415 => ScrapeUnblocker::UnsupportedContentError,
      422 => ScrapeUnblocker::ValidationError,
      429 => ScrapeUnblocker::RateLimitError,
      503 => ScrapeUnblocker::UpstreamOutageError,
      418 => ScrapeUnblocker::APIError
    }.each do |status, klass|
      client = make_client([{ status: status, body: "nope" }], max_retries: 0)
      err = assert_raises(klass) { client.get_page_source("https://example.com") }
      assert_equal status, err.status_code
    end
  end

  def test_billing_error_subclass_from_body
    {
      "Quota exceeded\n" => ScrapeUnblocker::QuotaExceededError,
      "Credit limit exceeded\n" => ScrapeUnblocker::CreditLimitExceededError,
      "Payment failed - update payment method\n" => ScrapeUnblocker::PaymentFailedError,
      "something new we do not know yet" => ScrapeUnblocker::PaymentRequiredError
    }.each do |body, klass|
      client = make_client([{ status: 402, body: body }], max_retries: 0)
      err = assert_raises(klass) { client.get_page_source("https://example.com") }
      assert_kind_of ScrapeUnblocker::PaymentRequiredError, err
      assert_equal 402, err.status_code
      assert_equal body, err.body
    end
  end

  def test_auth_error_subclass_from_body
    {
      "No valid subscription\n" => ScrapeUnblocker::NoSubscriptionError,
      "Unauthorized\n" => ScrapeUnblocker::AuthenticationError
    }.each do |body, klass|
      client = make_client([{ status: 401, body: body }], max_retries: 0)
      err = assert_raises(klass) { client.get_page_source("https://example.com") }
      assert_kind_of ScrapeUnblocker::AuthenticationError, err
      assert_equal 401, err.status_code
    end
  end

  # These clear when the key or billing state changes, never on a retry.
  def test_auth_and_billing_errors_are_not_retried
    [401, 402].each do |status|
      client = make_client([{ status: status, body: "Quota exceeded" }], max_retries: 3)
      assert_raises(ScrapeUnblocker::APIError) { client.get_page_source("https://example.com") }
      assert_equal 1, @urls.length
      @urls.clear
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
  def test_tiktok_plugin_endpoints
    client = make_client([
      { status: 200, body: JSON.generate("username" => "nasa", "videos" => []) },
      { status: 200, body: JSON.generate("id" => "7665075736742530317") },
      { status: 200, body: JSON.generate("hashtag" => "nasa", "videos" => []) }
    ])
    profile = client.tiktok_profile("nasa", max_videos: 5, video_details: false)
    video = client.tiktok_video("7665075736742530317", include_transcript: true, transcript_language: "eng")
    tag = client.tiktok_hashtag("#nasa", max_videos: 0)

    assert_equal "nasa", profile["username"]
    assert_equal "7665075736742530317", video["id"]
    assert_equal "nasa", tag["hashtag"]
    assert_includes @urls[0], "/social/tiktok-profile"
    assert_includes @urls[0], "username=nasa"
    assert_includes @urls[0], "max_videos=5"
    assert_includes @urls[0], "video_details=false"
    assert_includes @urls[1], "/social/tiktok-video"
    assert_includes @urls[1], "include_transcript=true"
    assert_includes @urls[1], "transcript_language=eng"
    assert_includes @urls[2], "/social/tiktok-hashtag"
    assert_includes @urls[2], "hashtag=%23nasa"
    assert_includes @urls[2], "max_videos=0"
    refute_includes @urls[2], "video_details="
  end

  def test_tiktok_search_and_comments
    client = make_client([
      { status: 200, body: JSON.generate("query" => "space", "results" => []) },
      { status: 200, body: JSON.generate("videoId" => "1", "comments" => []) }
    ])
    assert_equal "space", client.tiktok_search("space", max_results: 30, proxy_country: "US")["query"]
    assert_equal "1", client.tiktok_comments("7665075736742530317", max_comments: 100)["videoId"]
    assert_includes @urls[0], "/social/tiktok-search"
    assert_includes @urls[0], "query=space"
    assert_includes @urls[0], "max_results=30"
    assert_includes @urls[1], "/social/tiktok-comments"
    assert_includes @urls[1], "max_comments=100"
  end

end
