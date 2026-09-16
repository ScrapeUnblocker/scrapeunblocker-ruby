# frozen_string_literal: true

module ScrapeUnblocker
  # Southwest Airlines plugin endpoints (flights).
  class Southwest
    # @api private
    def initialize(client)
      @client = client
    end

    # Fetch Southwest Airlines flight quotes and return the raw booking JSON.
    #
    # +origin+ and +dest+ are IATA airport codes (e.g. "DAL", "HOU").
    # +depart_date+ (and the optional +return_date+) are "YYYY-MM-DD"; omit
    # +return_date+ for a one-way search. +adults+ is 1-8. +fare_type+ is
    # "dollars" (default) or "points". +proxy_country+ pins the exit (default
    # "US"). +max_attempts+ is 1-5.
    def flights(origin:, dest:, depart_date:, return_date: nil, adults: 1,
                fare_type: "dollars", proxy_country: "US", max_attempts: 3)
      @client.post_json("/flights/southwest-quotes",
                        origin: origin, dest: dest, depart_date: depart_date,
                        return_date: return_date, adults: adults,
                        fare_type: fare_type, proxy_country: proxy_country,
                        max_attempts: max_attempts)
    end
  end
end
