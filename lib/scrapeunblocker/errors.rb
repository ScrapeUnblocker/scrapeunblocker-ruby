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
  # are three, each raised as a dedicated subclass: QuotaExceededError,
  # CreditLimitExceededError and PaymentFailedError. Rescue this base class to
  # handle all three.
  #
  # When more than one applies, the most serious wins: failed payment outranks
  # credit limit, which outranks quota. All three lift by themselves once the
  # billing state changes - access returns within roughly a minute, with no key
  # change needed. Like a 401, a 402 is refused before anything is scraped, so
  # it is never billed. Retrying is pointless; fix the billing state first.
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
    402 => "Billing block - quota exceeded, credit limit exceeded, or a failed payment",
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

  # The three billing blocks share a status code and differ only in their
  # plain-text body. An unrecognised body falls back to PaymentRequiredError.
  def self.billing_error_class(body)
    text = (body || "").downcase
    return QuotaExceededError if text.include?("quota exceeded")
    return CreditLimitExceededError if text.include?("credit limit exceeded")
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

  # Build a typed error from an HTTP status code, response body and headers
  # (a Hash with lowercase names).
  def self.error_for_status(status, body, headers = {})
    target_error = target_not_found_error(status, body, headers || {})
    return target_error if target_error

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
