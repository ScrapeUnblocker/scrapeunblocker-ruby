# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "uri"
require "scrapeunblocker"

class PluginsTest < Minitest::Test
  def make_client
    @urls = []
    transport = lambda do |url, _headers|
      @urls << url
      { status: 200, body: JSON.generate("ok" => true) }
    end
    ScrapeUnblocker::Client.new(api_key: "test-key", transport: transport)
  end

  def query(index = 0)
    URI.decode_www_form(URI(@urls[index]).query || "")
  end

  def plugin_methods
    ScrapeUnblocker::Plugins.public_instance_methods(false) - [:plugin]
  end

  def test_covers_every_public_plugin_endpoint
    assert_operator plugin_methods.size, :>, 90
  end

  def test_every_method_posts_its_positional_arguments
    plugin_methods.each do |name|
      client = make_client
      positional = client.method(name).parameters.select { |kind, _| %i[req opt].include?(kind) }
      args = positional.each_index.map { |i| "v#{i}" }
      assert_equal({ "ok" => true }, client.public_send(name, *args), name)
      values = query.map(&:last)
      args.each { |arg| assert_includes values, arg, name }
    end
  end

  def test_options_are_sent_under_their_api_names
    client = make_client
    client.target_search("tv", sort: "price_low", max_results: 48)
    assert_includes @urls[0], "/marketplace/target-search?"
    assert_equal [%w[query tv], %w[sort price_low], %w[max_results 48]], query
  end

  def test_a_mode_method_pins_its_mode
    client = make_client
    client.woolworths_product("888137")
    assert_equal [%w[mode product], %w[product 888137]], query
  end

  def test_two_positional_arguments_and_a_false_flag
    client = make_client
    client.yelp_search("coffee", "San Francisco, CA", open_now: false)
    assert_equal [%w[mode search], %w[find_desc coffee], ["find_loc", "San Francisco, CA"], %w[open_now false]], query
  end

  def test_a_list_is_joined_where_the_api_takes_one_string
    client = make_client
    client.google_trends(%w[coffee tea], geo: "US")
    assert_equal [%w[keywords coffee,tea], %w[geo US]], query
  end

  def test_a_list_parameter_repeats_its_key
    client = make_client
    client.trustpilot_reviews("www.nike.com", stars: [4, 5])
    assert_equal [%w[company www.nike.com], %w[stars 4], %w[stars 5]], query
  end

  def test_optional_positional_argument_can_be_left_out
    client = make_client
    client.career_site_jobs(provider: "greenhouse", company: "stripe")
    assert_equal [%w[provider greenhouse], %w[company stripe]], query
  end

  def test_generic_plugin_call
    client = make_client
    client.plugin("/marketplace/target-search", query: "tv", sort: nil)
    assert_equal "https://api.scrapeunblocker.com/marketplace/target-search?query=tv", @urls[0]
  end

  def test_google_hotels_search_and_property
    client = make_client
    client.google_hotels("hotels in Paris", check_in: "2026-11-02", check_out: "2026-11-05", currency: "EUR")
    client.google_hotels_property("ChkIqp", adults: 1, children: "7,10")
    assert_includes @urls[0], "/travel/google-hotels?"
    assert_equal [["q", "hotels in Paris"], %w[check_in 2026-11-02], %w[check_out 2026-11-05], %w[currency EUR]], query
    assert_includes @urls[1], "/travel/google-hotels-property?"
    assert_equal [%w[property_token ChkIqp], %w[adults 1], %w[children 7,10]], query(1)
  end

  def test_google_news_search_or_section
    client = make_client
    client.google_news("tesla", when: "1d", max_results: 50)
    client.google_news(topic: "technology", gl: "gb")
    assert_equal [%w[q tesla], %w[when 1d], %w[max_results 50]], query
    assert_equal [%w[topic technology], %w[gl gb]], query(1)
  end

  def test_google_ads_transparency_and_advertisers
    client = make_client
    client.google_ads_transparency(domain: "nike.com", format: "video", include_preview: false)
    client.google_ads_transparency_advertisers("nike", max_results: 5)
    assert_includes @urls[0], "/ads/google-ads-transparency?"
    assert_equal [%w[domain nike.com], %w[format video], %w[include_preview false]], query
    assert_includes @urls[1], "/ads/google-ads-transparency-advertisers?"
    assert_equal [%w[q nike], %w[max_results 5]], query(1)
  end

  def test_shopee_search_and_product
    client = make_client
    client.shopee_search("lego", country: "my", sort: "sales", min_price: 10)
    client.shopee_product(shop_id: "442800909", item_id: "40270108836", country: "sg")
    assert_equal [%w[q lego], %w[country my], %w[sort sales], %w[min_price 10]], query
    assert_includes @urls[1], "/marketplace/shopee-product?"
    assert_equal [%w[shop_id 442800909], %w[item_id 40270108836], %w[country sg]], query(1)
  end

  def test_taobao_search_and_product
    client = make_client
    client.taobao_search("phone case", sort: "sales", price_max: 99.5, filter: "20000-88634403")
    client.taobao_product(url: "https://item.taobao.com/item.htm?id=765833709683")
    assert_equal [["q", "phone case"], %w[sort sales], %w[price_max 99.5], %w[filter 20000-88634403]], query
    assert_equal [%w[url https://item.taobao.com/item.htm?id=765833709683]], query(1)
  end

  def test_upwork_jobs_without_a_query
    client = make_client
    client.upwork_jobs(sort: "recency", job_type: "hourly", details: true)
    assert_includes @urls[0], "/jobs/upwork?"
    assert_equal [%w[job_type hourly], %w[sort recency], %w[details true]], query
  end

  def test_smyths_and_wish
    client = make_client
    client.smyths_search("lego", max_results: 24)
    client.wish_search("phone case", page: 2)
    assert_equal [%w[mode search], %w[query lego], %w[max_results 24]], query
    assert_equal [["query", "phone case"], %w[page 2]], query(1)
  end
end
