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
    assert_operator plugin_methods.size, :>, 100
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
end
