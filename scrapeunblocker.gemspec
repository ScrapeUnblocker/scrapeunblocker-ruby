# frozen_string_literal: true

require_relative "lib/scrapeunblocker/version"

Gem::Specification.new do |spec|
  spec.name = "scrapeunblocker"
  spec.version = ScrapeUnblocker::VERSION
  spec.authors = ["ScrapeUnblocker"]
  spec.email = ["support@scrapeunblocker.com"]

  spec.summary = "Official Ruby client for the ScrapeUnblocker web scraping API."
  spec.description = "JS-rendered pages that bypass Cloudflare, DataDome, " \
                     "PerimeterX and Akamai, plus Google SERP and Skyscanner " \
                     "flights/hotels/car-hire scraping as JSON."
  spec.homepage = "https://scrapeunblocker.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata = {
    "homepage_uri" => "https://scrapeunblocker.com",
    "source_code_uri" => "https://github.com/ScrapeUnblocker/scrapeunblocker-ruby",
    "documentation_uri" => "https://developers.scrapeunblocker.com",
    "changelog_uri" => "https://github.com/ScrapeUnblocker/scrapeunblocker-ruby/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/ScrapeUnblocker/scrapeunblocker-ruby/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb"] + ["README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]
end
