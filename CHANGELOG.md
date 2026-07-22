# Changelog

## 0.1.2 (2026-07-22)

- Added `oopbuy_search(keyword, ...)` for the new Oopbuy goods search plugin (`POST /goods/oopbuy-search`) - searches 1688, Taobao or the official channel and returns matched products (spu, title, price, monthSold, image, url) as a Hash.

## 0.1.1

- Added `google_local(keyword, ...)` for the new Google Local (Maps) plugin (`POST /maps/google-local`) - returns local business listings (name, rating, reviews, price, category, address, hours) as a Hash.

## 0.1.0

Initial release.

- `ScrapeUnblocker::Client` with `get_page_source`, `get_parsed`, `get_page_with_cookies`, `serp`, `get_image`.
- Skyscanner plugins: flights, hotels, car hire (quotes + locations).
- Typed error hierarchy and automatic retry on transient failures.
