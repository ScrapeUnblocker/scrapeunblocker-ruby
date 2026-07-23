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

## Google Local (Maps)

```ruby
local = su.google_local("coffee shops in chicago", proxy_country: "US", gl: "us")
local["results"].each { |biz| puts "#{biz['name']} #{biz['rating']} #{biz['address']}" }
```

## Oopbuy goods search

```ruby
goods = su.oopbuy_search("running shoes", channel: "1688", page: 1, page_size: 20, sort: "default")
goods["results"].each { |item| puts "#{item['title']} #{item['price']} #{item['url']}" }
```

`channel` is one of `"1688"` (default), `"taobao"` or `"official"`. `sort` is one of `"default"`, `"price_asc"`, `"price_desc"` or `"best_selling"`. `page_size` max is 60. Oopbuy trademark-blocks brand keywords at its own backend: those come back as a successful `200` with `keywordRejected: true` and an empty `results` array, not an error.

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

Non-2xx responses raise typed errors, all subclasses of `ScrapeUnblocker::Error`.

```ruby
begin
  html = su.get_page_source("https://example.com")
rescue ScrapeUnblocker::BlockedError
  # 403: the target blocked every bypass path (not billed)
rescue ScrapeUnblocker::PaymentRequiredError
  # 402: quota, credit limit, or a failed payment - fix billing
rescue ScrapeUnblocker::RateLimitError
  # 429: slow down
rescue ScrapeUnblocker::UpstreamOutageError
  # 503: the target site itself is down - retry later
end
```

| Error | Status | Meaning |
|---|---|---|
| `InvalidRequestError` | 400 | Bad URL, unsupported scheme, or the API key header was not sent |
| `AuthenticationError` | 401 | Key not recognised - typo, stray whitespace, or a rotated key |
| `NoSubscriptionError` | 401 | Key is fine, but the account has no active plan |
| `PaymentRequiredError` | 402 | Billing block - base class for the three below |
| `QuotaExceededError` | 402 | The plan's requests for this period are used up |
| `CreditLimitExceededError` | 402 | Unpaid balance is past the account's credit limit |
| `PaymentFailedError` | 402 | A card payment was declined three times |
| `BlockedError` | 403 | Blocked by bot protection on every path |
| `NotFoundError` | 404 | Page loaded but held no image (`get_image` only) |
| `BrowserTimeoutError` | 408 | Our browser run timed out before the page was ready |
| `UnsupportedContentError` | 415 | The URL serves something other than HTML |
| `ValidationError` | 422 | Missing or wrong-typed parameter; `body` holds the `detail` array |
| `RateLimitError` | 429 | Too many requests |
| `UpstreamOutageError` | 503 | The target origin is down |
| `ServerError` | 5xx | Unexpected server error, including a 504 upstream timeout |
| `TimeoutError` | - | This client gave up locally before the API answered |
| `ConnectionError` | - | Could not reach the API |

Transient failures (429, 502, 503, 504 and network errors) are retried automatically with exponential backoff. A 401 or 402 is never retried - it clears when the key or the billing state changes, not on another attempt. Neither is billed or counted against your quota, because the request is refused before anything is scraped.

### Billing errors (402)

The three billing blocks share a status code and differ only in their message, so the client raises a dedicated error for each:

```ruby
begin
  html = su.get_page_source("https://example.com")
rescue ScrapeUnblocker::QuotaExceededError
  # plan quota (plus any overage allowance) is used up for this period
rescue ScrapeUnblocker::CreditLimitExceededError
  # unpaid balance passed the account credit limit
rescue ScrapeUnblocker::PaymentFailedError
  # card declined three times - update the payment method
end
```

When more than one applies, the most serious wins: failed payment outranks credit limit, which outranks quota. All three lift by themselves once the billing state changes - access returns within about a minute, and the API key stays the same. One catch worth knowing: subscribing to a new plan does **not** clear `PaymentFailedError`, because the old unpaid invoice stays open until it is paid.

Full details for every status code: [developers.scrapeunblocker.com/errors](https://developers.scrapeunblocker.com/errors).

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
