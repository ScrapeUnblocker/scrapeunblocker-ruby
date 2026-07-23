# Changelog

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
