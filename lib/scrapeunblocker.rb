# frozen_string_literal: true

require_relative "scrapeunblocker/version"
require_relative "scrapeunblocker/errors"
require_relative "scrapeunblocker/parsed_page"
require_relative "scrapeunblocker/skyscanner"
require_relative "scrapeunblocker/client"

# Official Ruby client for the ScrapeUnblocker web scraping API.
#
#   require "scrapeunblocker"
#
#   su = ScrapeUnblocker::Client.new  # reads SCRAPEUNBLOCKER_KEY
#   html = su.get_page_source("https://example.com")
#   product = su.get_parsed("https://www.amazon.com/dp/B08N5WRWNW")
module ScrapeUnblocker
end
