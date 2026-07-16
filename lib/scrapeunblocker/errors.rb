# frozen_string_literal: true

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

  # The API key is missing, malformed, or not recognised (HTTP 401).
  class AuthenticationError < APIError; end

  # The request was rejected as invalid, e.g. a malformed URL (HTTP 400).
  class InvalidRequestError < APIError; end

  # The target site blocked every available bypass path (HTTP 403).
  # Blocked calls are not billed.
  class BlockedError < APIError; end

  # Too many requests against your account in a short window (HTTP 429).
  class RateLimitError < APIError; end

  # The origin site returned a server-side outage page (HTTP 503).
  class UpstreamOutageError < APIError; end

  # ScrapeUnblocker returned an unexpected 5xx error.
  class ServerError < APIError; end

  # The request did not complete within the configured timeout.
  class TimeoutError < Error; end

  # The client could not reach the ScrapeUnblocker API.
  class ConnectionError < Error; end

  # Build a typed error from an HTTP status code and response body.
  def self.error_for_status(status, body)
    snippet = (body || "").strip.gsub(/\s+/, " ")
    snippet = "#{snippet[0, 200]}..." if snippet.length > 200
    base = {
      400 => "Invalid request (bad URL or unsupported scheme)",
      401 => "Authentication failed - check your API key",
      403 => "Target blocked by bot protection on every bypass path",
      429 => "Rate limited - too many requests",
      503 => "Upstream origin returned a server-side outage page"
    }.fetch(status, "API returned HTTP #{status}")
    message = snippet.empty? ? base : "#{base}: #{snippet}"

    klass =
      case status
      when 400 then InvalidRequestError
      when 401 then AuthenticationError
      when 403 then BlockedError
      when 429 then RateLimitError
      when 503 then UpstreamOutageError
      else status >= 500 ? ServerError : APIError
      end

    klass.new(message, status_code: status, body: body)
  end
end
