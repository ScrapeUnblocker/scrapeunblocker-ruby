# frozen_string_literal: true

module ScrapeUnblocker
  # Structured data extracted from a page (#get_parsed).
  class ParsedPage
    # @return [String, nil] what the API classified the page as, e.g. "product"
    attr_reader :page_type
    # @return [String, nil] how the data was extracted
    attr_reader :source
    # @return the extracted fields
    attr_reader :data
    # @return [Hash] the full JSON payload as returned by the API
    attr_reader :raw
    # @return [String, nil] the rendered page when #data_extracted? is false
    attr_reader :html
    # @return [String, nil] the API's explanation when #data_extracted? is false
    attr_reader :detail

    def initialize(page_type:, source:, data:, raw:, data_extracted: true, html: nil, detail: nil)
      @page_type = page_type
      @source = source
      @data = data
      @raw = raw
      @data_extracted = data_extracted
      @html = html
      @detail = detail
    end

    # @return [Boolean] false when the page rendered but no structured data
    #   could be extracted from it (#data is then empty, #html holds the page)
    def data_extracted?
      @data_extracted
    end

    def self.from_hash(payload)
      inner = payload["data"].is_a?(Hash) ? payload["data"] : payload
      new(
        page_type: inner["page_type"],
        source: inner["source"],
        data: inner["data"],
        raw: payload,
        data_extracted: payload["data_extracted"] != false,
        html: payload["html"],
        detail: payload["detail"]
      )
    end
  end

  # HTML plus the cookies and proxy that served it (#get_page_with_cookies).
  class PageResult
    attr_reader :html, :cookies, :proxy, :raw

    def initialize(html:, cookies:, proxy:, raw:)
      @html = html
      @cookies = cookies
      @proxy = proxy
      @raw = raw
    end

    def self.from_hash(payload)
      new(
        html: payload["html"] || payload["page_source"] || payload["content"],
        cookies: payload["cookies"],
        proxy: payload["proxy"] || payload["proxy_address"],
        raw: payload
      )
    end
  end

  # One XHR/fetch response the page received (#get_page_with_xhr).
  # +status+ is 0 when the request failed without a response; +body+ is nil
  # when it was not returned, with +body_omitted+ saying why ("binary",
  # "size_limit", "in_flight", "redirect", "unavailable" or "request_failed").
  class XhrCall
    attr_reader :url, :method, :status, :content_type, :body, :body_omitted

    def initialize(url:, method:, status:, content_type: nil, body: nil, body_omitted: nil)
      @url = url
      @method = method
      @status = status
      @content_type = content_type
      @body = body
      @body_omitted = body_omitted
    end

    def self.from_hash(item)
      new(
        url: item["url"].to_s,
        method: (item["method"] || "GET").to_s,
        status: item["status"].to_i,
        content_type: item["content_type"],
        body: item["body"],
        body_omitted: item["body_omitted"]
      )
    end

    # The body parsed as JSON (raises JSON::ParserError / ArgumentError when it is not).
    def json
      raise ArgumentError, "no body (#{body_omitted || 'unavailable'})" if body.nil?

      JSON.parse(body)
    end
  end

  # A page plus the XHR/fetch responses it received (#get_page_with_xhr).
  class CapturedPage
    attr_reader :html, :xhr, :proxy, :raw

    def initialize(html:, xhr:, xhr_truncated:, proxy:, raw:)
      @html = html
      @xhr = xhr
      @xhr_truncated = xhr_truncated
      @proxy = proxy
      @raw = raw
    end

    # True when more responses matched than were returned.
    def xhr_truncated?
      @xhr_truncated
    end

    def self.from_hash(payload)
      new(
        html: payload["html"],
        xhr: (payload["xhr"] || []).map { |item| XhrCall.from_hash(item) },
        xhr_truncated: payload["xhr_truncated"] == true,
        proxy: payload["proxy"],
        raw: payload
      )
    end
  end
end
