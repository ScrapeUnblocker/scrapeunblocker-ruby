# frozen_string_literal: true

module ScrapeUnblocker
  # Skyscanner plugin endpoints (flights, hotels, car hire).
  class Skyscanner
    # @api private
    def initialize(client)
      @client = client
    end

    def flight_locations(q, params = {})
      @client.post_json("/flights/skyscanner-locations", { q: q }.merge(params))
    end

    def flights(params = {})
      @client.post_json("/flights/skyscanner-quotes", params)
    end

    def hotel_locations(q, params = {})
      @client.post_json("/hotels/skyscanner-locations", { q: q }.merge(params))
    end

    def hotels(params = {})
      @client.post_json("/hotels/skyscanner-quotes", params)
    end

    def carhire_locations(q, params = {})
      @client.post_json("/carhire/skyscanner-locations", { q: q }.merge(params))
    end

    def carhire(params = {})
      @client.post_json("/carhire/skyscanner-quotes", params)
    end
  end
end
