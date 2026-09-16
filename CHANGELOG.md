# Changelog

## 0.4.0 (2026-09-16)

- Added `southwest.flights(origin:, dest:, depart_date:, ...)` for the new Southwest Airlines plugin (`POST /flights/southwest-quotes`), reached through the new `su.southwest` namespace and mirroring `su.skyscanner`. `origin` and `dest` are IATA airport codes; `depart_date` and the optional `return_date` are `YYYY-MM-DD` (omit `return_date` for a one-way search). Optional `adults` (1-8, default 1), `fare_type` (`"dollars"` default or `"points"`), `proxy_country` (default `"US"`) and `max_attempts` (1-5, default 3). Returns the raw booking / shopping JSON as a Hash.

No breaking changes.

## 0.3.0 (2026-09-08)

- Added `tiktok_profile`, `tiktok_video`, `tiktok_hashtag`, `tiktok_search` and `tiktok_comments` for the new TikTok plugin: a creator's exact follower / like / video counts with their newest videos (up to 200), any video or photo post with exact plays, likes, comments, shares, saves and reposts, hashtags, music, play / download URLs, subtitle tracks and an optional transcript, a hashtag's total views and videos with its videos, keyword search in TikTok's own ranking, and the comments of any post. No login.

## 0.2.1 (2026-09-02)

- Added `meta_ad_library(advertiser, ...)` for the new Meta Ad Library plugin (`POST /ads/meta-ad-library`) - returns an advertiser's Meta (Facebook) Ad Library ads as a Hash. `advertiser` is required; optional filters `country`, `active_status`, `media_type` and `max_ads` are dropped when unset so the API applies its own defaults.

No breaking changes.

## 0.2.0 (2026-08-29)

- `get_page_source` now accepts `steps:` - an ordered Array of browser-action Hashes the API runs in the real browser after the page loads (`wait_for`, `wait_for_text`, `wait`, `click`, `type`, `select`, `press_key`, `scroll`). The array is JSON-encoded into the `steps` query parameter. Steps run once and are not idempotent; a failed step returns HTTP 422 and raises `ScrapeUnblocker::ValidationError`, whose `body` names the failed step (`step_index`, `action`, `reason`, `selector`, `html`).
- `get_page_source` now accepts `list_elements:` - pass `true` to get a JSON summary of the matched elements (`{"url", "count", "elements"}`) instead of HTML. When set, the method returns the parsed Hash rather than an HTML String, mirroring `get_parsed`.

No breaking changes.

## 0.1.9 (2026-08-28)

- Added `amazon_product` and `amazon_search` for the new Amazon plugin. `amazon_product(asin:/url:)` returns one product - title, brand, numeric price and currency, list price and savings, availability, rating, review count, seller, feature bullets, categories and images. `amazon_search(keyword, ...)` returns a keyword search's cards - asin, title, price, list price, rating, review count, a clean product URL, image and the sponsored/prime flags - on any of 20 regional marketplaces.
- Prices come back in the right currency automatically: `proxy_country` defaults to the marketplace's home country (amazon.com -> US, amazon.de -> DE), pinning the exit over our ISP pool.

## 0.1.8 (2026-07-31)

- Added `ebay_search` for the new eBay Search plugin: listings from any of the 19 regional eBay marketplaces as structured JSON - title, numeric price and currency, condition with a normalised `conditionCode`, seller username and feedback, shipping cost, sold/watcher/bid counts, image and a clean item URL.
- Filters map straight onto the plugin: `marketplace`, `condition`, `sort`, `listing_type`, `min_price`/`max_price`, `free_shipping`, `seller`, `category`, plus `page`/`page_size` (60, 120 or 240).
- The response carries `exactMatches`; it is `false` when eBay found no match for the keyword and answered with its own loosely-related suggestions.

No breaking changes.

## 0.1.7 (2026-07-27)

- Registry and README links to scrapeunblocker.com now carry UTM parameters so traffic from package registries is attributable. No functional changes.

## 0.1.6 (2026-07-23)

Version jumps from 0.1.2 to 0.1.6 so all four official SDKs (Python, Node.js, Ruby, PHP) share one version number from here on. Nothing was skipped - 0.1.3 to 0.1.5 were never released for Ruby.

- Added `PaymentRequiredError` for HTTP 402, which previously surfaced as a bare `APIError` with no explanation. The three billing blocks now each get their own subclass, picked from the response body: `QuotaExceededError` (`Quota exceeded`), `CreditLimitExceededError` (`Credit limit exceeded`) and `PaymentFailedError` (`Payment failed - update payment method`). Rescue `PaymentRequiredError` to handle all three.
- Added `NoSubscriptionError`, a subclass of `AuthenticationError`, for the 401 that means "the key is fine, the account has no active plan" (`No valid subscription`) as opposed to an unrecognised key.
- Added typed errors for the remaining documented status codes: `NotFoundError` (404), `BrowserTimeoutError` (408), `UnsupportedContentError` (415) and `ValidationError` (422). All previously raised a bare `APIError`.
- Error messages now describe every documented status code accurately - notably 400, which also covers a missing `x-scrapeunblocker-key` header, not just a bad URL.
- Documented the full error hierarchy in the README, including which errors are retried, which are billed, and how each 402 clears.
- Fixed the README claim that Oopbuy brand keywords return HTTP 422. They return a successful `200` with `keywordRejected: true` and an empty `results` array.

No breaking changes: every new class inherits from `APIError`, so existing `rescue ScrapeUnblocker::APIError` / `rescue ScrapeUnblocker::Error` handlers keep working unchanged.

## 0.1.2 (2026-07-22)

- Added `oopbuy_search(keyword, ...)` for the new Oopbuy goods search plugin (`POST /goods/oopbuy-search`) - searches 1688, Taobao or the official channel and returns matched products (spu, title, price, monthSold, image, url) as a Hash.

## 0.1.1

- Added `google_local(keyword, ...)` for the new Google Local (Maps) plugin (`POST /maps/google-local`) - returns local business listings (name, rating, reviews, price, category, address, hours) as a Hash.

## 0.1.0

Initial release.

- `ScrapeUnblocker::Client` with `get_page_source`, `get_parsed`, `get_page_with_cookies`, `serp`, `get_image`.
- Skyscanner plugins: flights, hotels, car hire (quotes + locations).
- Typed error hierarchy and automatic retry on transient failures.
