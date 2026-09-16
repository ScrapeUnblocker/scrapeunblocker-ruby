# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

require_relative "errors"
require_relative "parsed_page"
require_relative "skyscanner"
require_relative "southwest"
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

    # @return [Southwest] the Southwest Airlines plugin endpoints
    attr_reader :southwest

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
      @southwest = Southwest.new(self)
    end

    # Fetch a URL and return the fully rendered HTML.
    #
    # +steps+ is an ordered Array of browser-action Hashes the API runs in the
    # real browser after the page loads (each Hash carries an +action+ and its
    # fields): +wait_for+ {selector, selector_type?, timeout_ms?}, +wait_for_text+
    # {value, timeout_ms?}, +wait+ {value}, +click+ {selector, selector_type?,
    # timeout_ms?}, +type+ {selector, selector_type?, value, clear?, timeout_ms?},
    # +select+ {selector, selector_type?, value, timeout_ms?}, +press_key+ {value},
    # +scroll+ {value}. +selector_type+ is one of "css" (default), "xPath",
    # "className" or "tagName". The steps run once and are not idempotent; if a
    # step fails the API answers HTTP 422 with a JSON body naming the failed step,
    # which surfaces here as a ScrapeUnblocker::ValidationError.
    #
    # +list_elements+, when true, makes the API return a JSON summary of the
    # matched elements ({"url", "count", "elements"}) instead of HTML. This method
    # then returns that parsed Hash rather than an HTML String.
    def get_page_source(url, proxy_country: nil, time_sleep: nil, method: nil, value: nil, method_timeout: nil,
                        steps: nil, list_elements: nil)
      body = request("/getPageSource",
                     url: url, proxy_country: proxy_country, time_sleep: time_sleep,
                     method: method, value: value, method_timeout: method_timeout,
                     steps: (steps ? JSON.generate(steps) : nil),
                     list_elements: (list_elements ? true : nil))[:body]
      return JSON.parse(body) if list_elements

      body
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

    # Fetch an advertiser's Meta (Facebook) Ad Library ads and return them as a Hash.
    #
    # +advertiser+ is the advertiser name or page to look up. Optional filters:
    # +country+ (the Ad Library region), +active_status+ (active or inactive
    # ads), +media_type+ (image, video, etc.) and +max_ads+ (a cap on how many
    # ads to return). Unset filters are dropped from the request and the API
    # applies its own defaults.
    def meta_ad_library(advertiser, country: nil, active_status: nil, media_type: nil, max_ads: nil)
      post_json("/ads/meta-ad-library",
                advertiser: advertiser, country: country, active_status: active_status,
                media_type: media_type, max_ads: max_ads)
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

    # Search eBay and return the listings as a Hash.
    #
    # Each listing carries title, numeric price and currency, condition (with a
    # normalised conditionCode), seller username and feedback, shipping cost,
    # sold/watcher/bid counts, image and a clean item URL.
    #
    # +marketplace+ is a regional eBay host such as "ebay.com" (default) or
    # "ebay.de"; +condition+ is one of "new", "open_box", "refurbished", "used"
    # or "for_parts"; +sort+ is one of "best_match" (default), "newly_listed",
    # "ending_soon", "price_asc" or "price_desc"; +listing_type+ is "all"
    # (default), "buy_it_now" or "auction"; +page_size+ is 60, 120 or 240.
    #
    # When eBay finds no exact match it still serves a page of loosely related
    # suggestions, and the response then carries <tt>exactMatches: false</tt>.
    def ebay_search(keyword, marketplace: "ebay.com", page: 1, page_size: 60,
                    condition: nil, sort: "best_match", listing_type: "all",
                    min_price: nil, max_price: nil, free_shipping: false,
                    seller: nil, category: nil, proxy_country: nil)
      post_json("/marketplace/ebay-search",
                keyword: keyword, marketplace: marketplace, page: page,
                page_size: page_size, condition: condition, sort: sort,
                listing_type: listing_type, min_price: min_price,
                max_price: max_price,
                free_shipping: free_shipping ? true : nil,
                seller: seller, category: category,
                proxy_country: proxy_country)
    end

    # Scrape one Amazon product by ASIN or URL and return it as a Hash.
    #
    # Returns title, brand, numeric price and currency, list price and savings,
    # availability, rating, review count, seller, feature bullets, categories
    # and images. Prices come back in the marketplace's own currency:
    # +proxy_country+ defaults to the marketplace's home country
    # (amazon.com -> US), pinning the exit over the ISP pool. Pass either
    # +asin+ (with +marketplace+) or a full product +url+.
    def amazon_product(asin: nil, url: nil, marketplace: "amazon.com", proxy_country: nil)
      post_json("/marketplace/amazon-product",
                asin: asin, url: url, marketplace: marketplace,
                proxy_country: proxy_country)
    end

    # Search Amazon and return the result cards as an Array of Hashes.
    #
    # Each card carries asin, title, numeric price and currency, list price,
    # rating, review count, a clean product URL, image and the sponsored /
    # prime flags. +sort+ is "featured" (default), "price_asc", "price_desc",
    # "avg_review" or "newest". Prices are in the marketplace's own currency;
    # +proxy_country+ defaults to the marketplace's home country.
    def amazon_search(keyword, marketplace: "amazon.com", page: 1, sort: "featured",
                      min_price: nil, max_price: nil, proxy_country: nil)
      post_json("/marketplace/amazon-search",
                keyword: keyword, marketplace: marketplace, page: page,
                sort: sort, min_price: min_price, max_price: max_price,
                proxy_country: proxy_country)
    end

    # Fetch an image URL through the bypass chain and return its raw bytes.
    def get_image(url, proxy_country: nil)
      request("/getImage", url: url, proxy_country: proxy_country)[:body]
    end

    # @api private
    # Scrape a public TikTok creator profile and its newest videos.
    #
    # Returns the exact follower, following, like and video counts, bio, bio
    # link, verified / private / organization / seller flags, avatar and a
    # +videos+ array of the creator's newest posts (up to 200), each in the
    # full #tiktok_video shape. No login.
    def tiktok_profile(username, max_videos: 10, video_details: true, proxy_country: nil)
      post_json("/social/tiktok-profile",
                username: username, max_videos: max_videos,
                video_details: video_details ? nil : false,
                proxy_country: proxy_country)
    end

    # Scrape one TikTok video or photo post: exact plays, likes, comments,
    # shares, saves and reposts, hashtags, mentions, author, music, play /
    # download URLs, subtitle tracks and, with +include_transcript+, the
    # transcript as text.
    def tiktok_video(url, include_transcript: false, transcript_language: nil, proxy_country: nil)
      post_json("/social/tiktok-video",
                url: url, include_transcript: include_transcript ? true : nil,
                transcript_language: transcript_language, proxy_country: proxy_country)
    end

    # Scrape a TikTok hashtag: total views and videos plus its videos (up to 200).
    def tiktok_hashtag(hashtag, max_videos: 10, video_details: true, proxy_country: nil)
      post_json("/social/tiktok-hashtag",
                hashtag: hashtag, max_videos: max_videos,
                video_details: video_details ? nil : false,
                proxy_country: proxy_country)
    end

    # Search TikTok videos by keyword. Runs in a browser session that clears
    # TikTok's captcha, so +results+ carry TikTok's own ranking (region via
    # +proxy_country+), each in the full #tiktok_video shape. 20-45 s.
    def tiktok_search(query, max_results: 20, proxy_country: nil)
      post_json("/social/tiktok-search",
                query: query, max_results: max_results, proxy_country: proxy_country)
    end

    # Scrape the comments of a TikTok post (text, date, likes, reply count,
    # author, creator flags, preloaded replies) plus +totalComments+ and
    # +hasMore+. Runs in a browser session that clears TikTok's captcha. 20-45 s.
    def tiktok_comments(url, max_comments: 50, proxy_country: nil)
      post_json("/social/tiktok-comments",
                url: url, max_comments: max_comments, proxy_country: proxy_country)
    end

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
