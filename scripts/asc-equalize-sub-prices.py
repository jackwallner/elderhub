#!/usr/bin/env python3
"""Fill per-territory subscription prices from the USA base price.

Setting only the USA price does NOT auto-populate the other territories: the
subscription stays at MISSING_METADATA (and so is never served to StoreKit)
until every available territory has a price row. Apple exposes the equivalent
price point per territory as the USA point's `equalizations`.

Idempotent; skips territories that already have a price.
"""

import os
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from asc_lib import ASC  # noqa: E402

APP_ID = "6796916172"
USA_PRICES = {
    "com.jackwallner.aging.pro.monthly": "4.99",
    "com.jackwallner.aging.pro.yearly": "14.99",
}


def priced_territories(asc: ASC, sub_id: str) -> set[str]:
    priced: set[str] = set()
    path = f"/subscriptions/{sub_id}/prices"
    page = asc.get(path, include="territory", limit=200)
    while True:
        for included in page.get("included") or []:
            if included["type"] == "territories":
                priced.add(included["id"])
        next_url = (page.get("links") or {}).get("next")
        if not next_url:
            return priced
        page = asc._request("GET", next_url)


def main() -> None:
    asc = ASC()

    for group in asc.get(f"/apps/{APP_ID}/subscriptionGroups", limit=20).get("data", []):
        for sub in asc.get(f"/subscriptionGroups/{group['id']}/subscriptions", limit=20).get("data", []):
            product_id = sub["attributes"]["productId"]
            target = USA_PRICES.get(product_id)
            if not target:
                continue

            priced = priced_territories(asc, sub["id"])
            print(f"{product_id}: {len(priced)} territories already priced")

            points = asc.get_all(
                f"/subscriptions/{sub['id']}/pricePoints",
                limit=200,
                **{"filter[territory]": "USA"},
            )
            usa_point = next(
                p for p in points if p["attributes"]["customerPrice"] == target
            )

            equalizations = asc.get_all(
                f"/subscriptionPricePoints/{urllib.parse.quote(usa_point['id'], safe='')}/equalizations",
                include="territory",
                limit=200,
            )

            created = 0
            failed = 0
            for point in equalizations:
                territory = (
                    (point.get("relationships") or {}).get("territory", {}).get("data") or {}
                ).get("id")
                if not territory or territory in priced:
                    continue
                try:
                    asc.post(
                        "/subscriptionPrices",
                        {
                            "data": {
                                "type": "subscriptionPrices",
                                "relationships": {
                                    "subscription": {
                                        "data": {"type": "subscriptions", "id": sub["id"]}
                                    },
                                    "subscriptionPricePoint": {
                                        "data": {
                                            "type": "subscriptionPricePoints",
                                            "id": point["id"],
                                        }
                                    },
                                },
                            }
                        },
                    )
                    created += 1
                except SystemExit as error:
                    failed += 1
                    print(f"  {territory}: {str(error)[:120]}", file=sys.stderr)

            print(f"{product_id}: posted {created} territory prices ({failed} failed)")

    print("\nDone.")


if __name__ == "__main__":
    main()
