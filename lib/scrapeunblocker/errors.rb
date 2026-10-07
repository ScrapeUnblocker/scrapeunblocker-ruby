# frozen_string_literal: true

require "json"

module ScrapeUnblocker
  # Base class for every error raised by this library.
  class Error < StandardError; end

  # An error response returned by the ScrapeUnblocker API.
  class APIError < Error
    attr_reader :status_code, :body

    def initialize(message, status_code:, body: nil)
      super(message)
      @status_code = status_code
      @body = body
    end
  end

  # The API key was rejected (HTTP 401).
  #
  # Two cases produce a 401: an unrecognised key ("Unauthorized" - a typo,
  # trailing whitespace, an empty value, or a key rotated in the dashboard),
  # and a valid key on an account with no plan, which raises the
  # NoSubscriptionError subclass. Omitting the key header entirely is a 400,
  # not a 401. Nothing is scraped for a 401, so it is not billed.
  class AuthenticationError < APIError; end

  # The key is valid but the account has no active plan (HTTP 401).
  #
  # Raised when the API answers a 401 with "No valid subscription". Pick a plan
  # at https://app.scrapeunblocker.com - access resumes within about a minute,
  # and the key does not change.
  class NoSubscriptionError < AuthenticationError; end

  # The account has a billing problem (HTTP 402).
  #
  # Credentials are fine - the request was stopped for a billing reason. There
  # are four, each raised as a dedicated subclass: QuotaExceededError,
  # CreditLimitExceededError, BudgetExceededError and PaymentFailedError.
  # Rescue this base class to handle all four.
  #
  # When more than one applies, the most serious wins: failed payment outranks
  # credit limit, which outranks quota, which outranks your own budget limit.
  # All four lift by themselves once the billing state changes - access returns
  # within roughly a minute, with no key change needed. Like a 401, a 402 is
  # refused before anything is scraped, so it is never billed. Retrying is
  # pointless; fix the billing state first.
  class PaymentRequiredError < APIError; end

  # Every request the plan allows this period has been used (HTTP 402).
  #
  # On plans that permit overages this only fires past the quota *plus* the
  # overage allowance; inside that band requests still succeed and the extra
  # usage is invoiced. Active coupon credit is spent before plan quota. The
  # counter resets on the subscription's anniversary day, not the first of the
  # month.
  class QuotaExceededError < PaymentRequiredError; end

  # The unpaid balance has passed the account's credit limit (HTTP 402).
  #
  # The balance counted here is the amount remaining on open invoices plus
  # metered usage already consumed but not yet invoiced. Outstanding invoices
  # are charged automatically when this triggers, so with a working card it
  # usually clears itself within about a minute.
  class CreditLimitExceededError < PaymentRequiredError; end

  # This billing period's spend reached the monthly budget limit you set
  # (HTTP 402).
  #
  # The limit is set in your profile (EUR, excluding VAT), and spend is counted
  # the way the invoice is: the plan's fixed monthly fee, if any, plus the
  # requests billed on top of it. Requests paid from coupon credit do not count.
  # The key works again at the start of the next billing period, or within
  # about a minute after you raise or remove the limit at
  # https://app.scrapeunblocker.com/dashboard/profile.
  class BudgetExceededError < PaymentRequiredError; end

  # A card payment has been declined three times (HTTP 402).
  #
  # Those attempts are the payment provider's automatic retries spread over
  # several days, so a card has been failing for a while. Subscribing to a new
  # plan does NOT clear this: the old unpaid invoice stays open, and the block
  # stays until that specific invoice is paid.
  class PaymentFailedError < PaymentRequiredError; end

  # The request was rejected as invalid (HTTP 400).
  #
  # Raised for a malformed URL or unsupported scheme, for a missing
  # x-scrapeunblocker-key header ("Missing x-scrapeunblocker-key"), and for a
  # URL that belongs to a dedicated plugin - the response names the endpoint to
  # use instead.
  class InvalidRequestError < APIError; end

  # Something the call asked for does not exist (HTTP 404).
  #
  # #get_image raises it when the page rendered but held no <img> tag, and
  # plugin methods raise it when the item they look up does not exist. When the
  # target page itself answered 404 or 410, the more specific
  # TargetNotFoundError subclass is raised instead.
  class NotFoundError < APIError; end

  # The target page itself does not exist (HTTP 404 or 410).
  #
  # Raised by #get_page_source, #get_parsed and #get_page_with_cookies when the
  # site you asked for answered 404 or 410 on its own. The API passes that
  # status through and marks it with the X-Origin-Status header, which is how
  # this is told apart from an API-side 404. It is the target's final answer,
  # not a block, so it is never retried - and the call is billed, because the
  # page was fetched and delivered.
  #
  # +origin_status+ is the status the target answered with (404 or 410),
  # +html+ the target's own not-found page as served (can be empty; nil when
  # the body is a parsed-data JSON payload), and +destination_url+ the URL the
  # target answered for, when the API sent X-Destination-URL.
  class TargetNotFoundError < NotFoundError
    attr_reader :origin_status, :html, :destination_url

    def initialize(message, status_code:, origin_status:, body: nil, html: nil, destination_url: nil)
      super(message, status_code: status_code, body: body)
      @origin_status = origin_status
      @html = html
      @destination_url = destination_url
    end
  end

  # The browser run did not finish in time on our side (HTTP 408).
  #
  # Distinct from TimeoutError, which is this client giving up locally. Here
  # the API answered - it just could not render the page in time.
  class BrowserTimeoutError < APIError; end

  # The URL serves something other than HTML (HTTP 415).
  # The message names the content type found. For images, use #get_image.
  class UnsupportedContentError < APIError; end

  # A request parameter is missing or has the wrong type (HTTP 422).
  #
  # Unlike the other errors the body is JSON, with a "detail" array pinpointing
  # each problem field. Read it from #body.
  class ValidationError < APIError; end

  # Deprecated: the API no longer sends this 422.
  #
  # A page that rendered but held no structured data now comes back from
  # #get_parsed as a normal ParsedPage with #data_extracted? false and the page
  # on #html (a billed 200). The class stays so existing rescue clauses keep
  # loading; it is raised only for a legacy 422 body of
  # {"error": "no_data_extracted", "detail": ...}.
  class NoDataExtractedError < ValidationError
    attr_reader :detail

    def initialize(message, status_code:, body: nil, detail: nil)
      super(message, status_code: status_code, body: body)
      @detail = detail
    end
  end

  # The target site blocked every available bypass path (HTTP 403).
  # Blocked calls are not billed.
  class BlockedError < APIError; end

  # Too many requests against your account in a short window (HTTP 429).
  class RateLimitError < APIError; end

  # The origin site returned a server-side outage page (HTTP 503).
  class UpstreamOutageError < APIError; end

  # ScrapeUnblocker returned an unexpected 5xx error.
  # Also covers the 504 returned when a SERP fetch times out upstream.
  class ServerError < APIError; end

  # The request did not complete within the configured timeout.
  class TimeoutError < Error; end

  # The client could not reach the ScrapeUnblocker API.
  class ConnectionError < Error; end

  BASE_MESSAGES = {
    400 => "Invalid request (bad URL, unsupported scheme, or missing API key header)",
    401 => "Authentication failed - key not recognised, or account has no active plan",
    402 => "Billing block - quota exceeded, credit limit exceeded, budget limit reached, or a failed payment",
    403 => "Target blocked by bot protection on every bypass path",
    404 => "Requested element not found on the page",
    408 => "Browser run timed out before the page was ready",
    415 => "URL does not serve HTML",
    422 => "Validation error - see the detail array in the response body",
    429 => "Rate limited - too many requests",
    503 => "Upstream origin returned a server-side outage page",
    504 => "Fetch timed out upstream"
  }.freeze
  private_constant :BASE_MESSAGES

  # A 401 is either an unknown key or a recognised key on an account without a
  # plan, and only the body tells them apart. Anything unrecognised stays on
  # the general AuthenticationError rather than guessing.
  def self.auth_error_class(body)
    (body || "").downcase.include?("no valid subscription") ? NoSubscriptionError : AuthenticationError
  end
  private_class_method :auth_error_class

  # The four billing blocks share a status code and differ only in their
  # plain-text body. An unrecognised body falls back to PaymentRequiredError.
  def self.billing_error_class(body)
    text = (body || "").downcase
    return QuotaExceededError if text.include?("quota exceeded")
    return CreditLimitExceededError if text.include?("credit limit exceeded")
    return BudgetExceededError if text.include?("user set budget exceeded")
    return PaymentFailedError if text.include?("payment failed")

    PaymentRequiredError
  end
  private_class_method :billing_error_class

  # The API passes a target's "page does not exist" answer through with its
  # status and an X-Origin-Status header. A 404 without that header is the
  # API's own (a plugin lookup, a missing element) and returns nil so the
  # general NotFoundError applies.
  def self.target_not_found_error(status, body, headers)
    origin = headers["x-origin-status"]
    return nil unless [404, 410].include?(status) && origin && !origin.to_s.empty?

    origin_status = Integer(origin.to_s, exception: false) || status
    html = body
    begin
      data = JSON.parse(body.to_s)
      html = data["html"].is_a?(String) ? data["html"] : nil if data.is_a?(Hash)
    rescue JSON::ParserError
      # Not JSON: the body is the target's own page.
    end
    message = "Target page does not exist (HTTP #{origin_status}). This is the " \
              "target's own answer, not a block; the call is billed."
    TargetNotFoundError.new(message, status_code: status, body: body, origin_status: origin_status,
                                     html: html, destination_url: headers["x-destination-url"])
  end
  private_class_method :target_not_found_error

  # Maps a legacy 422 {"error": "no_data_extracted", "detail"} body; the API now
  # answers an empty parse with a 200 (data_extracted: false). Anything else
  # returns nil so the general ValidationError applies.
  def self.no_data_extracted_error(status, body)
    return nil unless status == 422

    data = begin
      JSON.parse(body.to_s)
    rescue JSON::ParserError
      nil
    end
    return nil unless data.is_a?(Hash) && data["error"] == "no_data_extracted"

    detail = data["detail"].is_a?(String) && !data["detail"].empty? ? data["detail"] : nil
    message = detail || "The page was rendered, but no structured data could be extracted from it. Not billed."
    message = "#{message} Not billed." unless message.downcase.include?("not billed")
    NoDataExtractedError.new(message, status_code: status, body: body, detail: detail)
  end
  private_class_method :no_data_extracted_error

  # Build a typed error from an HTTP status code, response body and headers
  # (a Hash with lowercase names).
  def self.error_for_status(status, body, headers = {})
    target_error = target_not_found_error(status, body, headers || {})
    return target_error if target_error

    no_data_error = no_data_extracted_error(status, body)
    return no_data_error if no_data_error

    snippet = (body || "").strip.gsub(/\s+/, " ")
    snippet = "#{snippet[0, 200]}..." if snippet.length > 200
    base = BASE_MESSAGES.fetch(status, "API returned HTTP #{status}")
    message = snippet.empty? ? base : "#{base}: #{snippet}"

    klass =
      case status
      when 400 then InvalidRequestError
      when 401 then auth_error_class(body)
      when 402 then billing_error_class(body)
      when 403 then BlockedError
      when 404 then NotFoundError
      when 408 then BrowserTimeoutError
      when 415 then UnsupportedContentError
      when 422 then ValidationError
      when 429 then RateLimitError
      when 503 then UpstreamOutageError
      else status >= 500 ? ServerError : APIError
      end

    klass.new(message, status_code: status, body: body)
  end
end
