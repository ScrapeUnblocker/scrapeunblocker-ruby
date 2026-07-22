# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

require_relative "errors"
require_relative "parsed_page"
require_relative "skyscanner"
require_relative "version"

module ScrapeUnblocker
  # Client for the ScrapeUnblocker API.
  #
  #   su = ScrapeUnblocker::Client.new(api_key: "YOUR_API_KEY")
  #   html = su.get_page_source("https://example.com")
  class Client
    DEFAULT_BASE_URL = "https://api.scrapeunblocker.com"
    API_KEY_HEADER = "x-scrapeunblocker-key"
    RETRYABLE = [429, 502, 503, 504].freeze

    # @return [Skyscanner] the Skyscanner plugin endpoints
    attr_reader :skyscanner

    def initialize(api_key: nil, base_url: DEFAULT_BASE_URL, timeout: 180, max_retries: 2, transport: nil)
      @api_key = api_key || ENV["SCRAPEUNBLOCKER_KEY"]
      if @api_key.nil? || @api_key.empty?
        raise Error, "No API key provided. Pass api_key: or set the " \
                     "SCRAPEUNBLOCKER_KEY environment variable. Get your key " \
                     "at https://app.scrapeunblocker.com"
      end
      @base_url = base_url.sub(%r{/+\z}, "")
      @timeout = timeout
      @max_retries = max_retries
      @transport = transport || method(:net_http_transport)
      @skyscanner = Skyscanner.new(self)
    end

    # Fetch a URL and return the fully rendered HTML.
    def get_page_source(url, proxy_country: nil, time_sleep: nil, method: nil, value: nil, method_timeout: nil)
      request("/getPageSource",
              url: url, proxy_country: proxy_country, time_sleep: time_sleep,
              method: method, value: value, method_timeout: method_timeout)[:body]
    end

    # Fetch a URL and return structured JSON instead of HTML.
    def get_parsed(url, proxy_country: nil, time_sleep: nil, refresh_rules: false, rules_hint: nil)
      body = request("/getPageSource",
                     url: url, parsed_data: true, proxy_country: proxy_country,
                     time_sleep: time_sleep,
                     refresh_rules: (refresh_rules ? true : nil),
                     rules_hint: rules_hint)[:body]
      ParsedPage.from_hash(JSON.parse(body))
    end

    # Fetch a URL and also return the cookies and proxy that served it.
    def get_page_with_cookies(url, proxy_country: nil, time_sleep: nil)
      body = request("/getPageSource",
                     url: url, get_cookies: true, proxy_country: proxy_country,
                     time_sleep: time_sleep)[:body]
      PageResult.from_hash(JSON.parse(body))
    end

    # Run a Google search and return the parsed SERP as a Hash.
    def serp(keyword, proxy_country: nil, pages_to_check: 1, wait_after_load: 0, captcha_pause: 0)
      post_json("/serpApi",
                keyword: keyword, proxy_country: proxy_country,
                pages_to_check: pages_to_check,
                wait_after_load: (wait_after_load.zero? ? nil : wait_after_load),
                captcha_pause: (captcha_pause.zero? ? nil : captcha_pause))
    end

    # Search Google Local (Maps) and return the businesses as a Hash.
    #
    # Returns up to ~20 businesses, each with name, rating, reviews, price,
    # category, address, hours and a top review snippet. Local results are
    # location-sensitive, so set +proxy_country+ (and optionally +gl+).
    def google_local(keyword, proxy_country: nil, hl: nil, gl: nil)
      post_json("/maps/google-local",
                keyword: keyword, proxy_country: proxy_country, hl: hl, gl: gl)
    end

    # Search Oopbuy (1688, Taobao or official channel) and return the goods as a Hash.
    #
    # Returns matched products, each with spu, channel, title, titleCn, price,
    # originalPrice, priceCny, monthSold, image and url. +channel+ is one of
    # "1688" (default), "taobao" or "official"; +sort+ is one of "default",
    # "price_asc", "price_desc" or "best_selling". +page_size+ max is 60.
    # Brand keywords return HTTP 422.
    def oopbuy_search(keyword, channel: "1688", page: 1, page_size: 20, sort: "default", proxy_country: nil)
      post_json("/goods/oopbuy-search",
                keyword: keyword, channel: channel, page: page,
                page_size: page_size, sort: sort, proxy_country: proxy_country)
    end

    # Fetch an image URL through the bypass chain and return its raw bytes.
    def get_image(url, proxy_country: nil)
      request("/getImage", url: url, proxy_country: proxy_country)[:body]
    end

    # @api private
    def post_json(path, params)
      JSON.parse(request(path, params)[:body])
    end

    private

    def request(path, params)
      url = "#{@base_url}#{path}?#{build_query(params)}"
      headers = {
        API_KEY_HEADER => @api_key,
        "User-Agent" => "scrapeunblocker-ruby/#{VERSION}",
        "Accept" => "*/*"
      }

      attempt = 0
      loop do
        result = @transport.call(url, headers)
        status = result[:status].to_i
        body = result[:body].to_s

        if RETRYABLE.include?(status) && attempt < @max_retries
          sleep([0.5 * (2**attempt), 8.0].min)
          attempt += 1
          next
        end

        return { status: status, body: body } if status >= 200 && status < 300

        raise ScrapeUnblocker.error_for_status(status, body)
      end
    end

    def build_query(params)
      params.each_with_object([]) do |(key, value), acc|
        next if value.nil?

        value = value ? "true" : "false" if value == true || value == false
        acc << "#{key}=#{URI.encode_www_form_component(value.to_s)}"
      end.join("&")
    end

    def net_http_transport(url, headers)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 30
      http.read_timeout = @timeout

      request = Net::HTTP::Post.new(uri.request_uri)
      headers.each { |k, v| request[k] = v }

      begin
        response = http.request(request)
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise TimeoutError, "Request timed out after #{@timeout}s: #{e.message}"
      rescue StandardError => e
        raise ConnectionError, "Could not reach the API: #{e.message}"
      end

      { status: response.code.to_i, body: response.body }
    end
  end
end
