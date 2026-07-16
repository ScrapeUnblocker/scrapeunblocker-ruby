# ScrapeUnblocker Ruby client

Official Ruby client for the [ScrapeUnblocker](https://scrapeunblocker.com) web scraping API.

Every request is fully JavaScript-rendered in a real browser and routed through premium proxies, so it bypasses Cloudflare, DataDome, PerimeterX, Akamai, Kasada and similar anti-bot systems - from one simple call. You are only billed for successful requests.

- **Highest success rate on the market** (95%+ on live production traffic)
- **Rendered HTML or parsed JSON** - no per-site parsers to maintain
- Zero dependencies (uses the standard library), typed errors

## Install

```bash
gem install scrapeunblocker
```

Or in a Gemfile:

```ruby
gem "scrapeunblocker"
```

Requires Ruby 2.7+.

## Quickstart

```ruby
require "scrapeunblocker"

su = ScrapeUnblocker::Client.new # reads SCRAPEUNBLOCKER_KEY, or Client.new(api_key: "YOUR_API_KEY")

# Rendered HTML for any URL
html = su.get_page_source("https://example.com")

# Structured JSON instead of HTML (products, listings, search results, ...)
product = su.get_parsed("https://www.amazon.com/dp/B08N5WRWNW")
puts product.page_type # "product"
p product.data
```

Get your API key at [app.scrapeunblocker.com](https://app.scrapeunblocker.com). The free trial does not require a credit card.

## Authentication

Set an environment variable and the client picks it up:

```bash
export SCRAPEUNBLOCKER_KEY="YOUR_API_KEY"
```

```ruby
su = ScrapeUnblocker::Client.new # reads SCRAPEUNBLOCKER_KEY
```

## Fetch rendered HTML

```ruby
html = su.get_page_source(
  "https://www.nordstrom.com/browse/women/clothing/dresses",
  proxy_country: "US", # route through a specific country
  time_sleep: 3        # wait extra seconds after load
)
```

## Get parsed JSON

```ruby
result = su.get_parsed("https://www.walmart.com/ip/12345")
puts result.page_type # e.g. "product"
puts result.source    # how it was extracted
p result.data         # the fields

# If a parse ever comes back wrong, force a fresh set of rules:
fresh = su.get_parsed(url, refresh_rules: true, rules_hint: "price is missing")
```

## Google search (SERP)

```ruby
serp = su.serp("web scraping api", pages_to_check: 2, proxy_country: "US")
```

## Cookies and the serving proxy

```ruby
page = su.get_page_with_cookies("https://example.com")
puts page.html
p page.cookies
puts page.proxy
```

## Images

```ruby
bytes = su.get_image("https://example.com/photo.jpg")
File.binwrite("photo.jpg", bytes)
```

## Skyscanner plugins

Flights, hotels and car hire as JSON:

```ruby
locations = su.skyscanner.flight_locations("London")

flights = su.skyscanner.flights(
  origin: "London", dest: "New York",
  depart_date: "2026-09-01", adults: 1, currency: "USD"
)

hotels = su.skyscanner.hotels(destination: "Madrid", checkin: "2026-09-01", checkout: "2026-09-03")
cars = su.skyscanner.carhire(pickup: "Madrid", pickup_datetime: "2026-09-01T10:00", dropoff_datetime: "2026-09-03T10:00")
```

## Error handling

Non-2xx responses raise typed errors, all subclasses of `ScrapeUnblocker::Error`. Transient failures (429, 502, 503, 504 and network errors) are retried automatically with exponential backoff.

```ruby
begin
  html = su.get_page_source("https://example.com")
rescue ScrapeUnblocker::BlockedError
  # 403: the target blocked every bypass path (not billed)
rescue ScrapeUnblocker::RateLimitError
  # 429: slow down
rescue ScrapeUnblocker::UpstreamOutageError
  # 503: the target site itself is down - retry later
end
```

| Error | Status | Meaning |
|---|---|---|
| `InvalidRequestError` | 400 | Bad URL or unsupported scheme |
| `AuthenticationError` | 401 | Missing or invalid API key |
| `BlockedError` | 403 | Blocked by bot protection on every path |
| `RateLimitError` | 429 | Too many requests |
| `UpstreamOutageError` | 503 | The target origin is down |
| `ServerError` | 5xx | Unexpected server error |
| `TimeoutError` | - | Request exceeded the timeout |
| `ConnectionError` | - | Could not reach the API |

## Configuration

```ruby
ScrapeUnblocker::Client.new(
  api_key: nil,        # or SCRAPEUNBLOCKER_KEY env var
  base_url: "https://api.scrapeunblocker.com",
  timeout: 180,        # seconds; protected pages can be slow
  max_retries: 2
)
```

## Links

- Documentation: https://developers.scrapeunblocker.com
- Website: https://scrapeunblocker.com
- Dashboard: https://app.scrapeunblocker.com

## License

MIT
