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

    def initialize(page_type:, source:, data:, raw:)
      @page_type = page_type
      @source = source
      @data = data
      @raw = raw
    end

    def self.from_hash(payload)
      inner = payload["data"].is_a?(Hash) ? payload["data"] : payload
      new(
        page_type: inner["page_type"],
        source: inner["source"],
        data: inner["data"],
        raw: payload
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
end
