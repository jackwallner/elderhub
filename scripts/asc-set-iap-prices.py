#!/usr/bin/env python3
"""Set USD prices and 1-week free trials for the Elderhub products.

Base territory is USA; Apple's automatic equalization covers everything else.
PPP overrides are applied later by the fleet-wide pricing tooling in ~/ios/pricing.

Idempotent. Run after asc-setup-iap.py.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from asc_lib import ASC  # noqa: E402

APP_ID = "6796916172"
BASE_TERRITORY = "USA"
DRY_RUN = os.environ.get("DRY_RUN") == "1"

# Elderhub launch prices. Keep these aligned with ASC and Products.storekit.
SUB_PRICES = {
    "com.jackwallner.aging.pro.monthly": "9.99",
    "com.jackwallner.aging.pro.yearly": "39.99",
}
LIFETIME_PRICE = "89.99"
LIFETIME_PRODUCT = "com.jackwallner.aging.pro.lifetime"
V2 = "https://api.appstoreconnect.apple.com/v2"


def log(message: str) -> None:
    print(("[dry-run] " if DRY_RUN else "") + message)


def find_price_point(points: list[dict], target: str) -> dict | None:
    for point in points:
        if point["attributes"].get("customerPrice") == target:
            return point
    return None


def ensure_availability(asc: ASC, sub_id: str, product_id: str) -> None:
    """Make the subscription available in every territory.

    Prices cannot be attached before availability exists: ASC rejects the price
    point with a generic "problem processing the pricing information" 409.
    """
    existing = asc.get_optional(f"/subscriptions/{sub_id}/subscriptionAvailability")
    if existing.get("data"):
        log(f"  availability exists: {product_id}")
        return

    log(f"  setting availability (all territories): {product_id}")
    if DRY_RUN:
        return

    territories = [t["id"] for t in asc.get_all("/territories", limit=200)]
    asc.post(
        "/subscriptionAvailabilities",
        {
            "data": {
                "type": "subscriptionAvailabilities",
                "attributes": {"availableInNewTerritories": True},
                "relationships": {
                    "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                    "availableTerritories": {
                        "data": [{"type": "territories", "id": t} for t in territories]
                    },
                },
            }
        },
    )


def set_subscription_prices(asc: ASC) -> None:
    groups = asc.get(f"/apps/{APP_ID}/subscriptionGroups", limit=20).get("data", [])
    for group in groups:
        subs = asc.get(f"/subscriptionGroups/{group['id']}/subscriptions", limit=20).get("data", [])
        for sub in subs:
            product_id = sub["attributes"].get("productId")
            target = SUB_PRICES.get(product_id)
            if not target:
                continue

            ensure_availability(asc, sub["id"], product_id)

            existing = asc.get(f"/subscriptions/{sub['id']}/prices", limit=20).get("data", [])
            if existing:
                log(f"price already set: {product_id}")
                continue

            points = asc.get_all(
                f"/subscriptions/{sub['id']}/pricePoints",
                limit=200,
                **{"filter[territory]": BASE_TERRITORY},
            )
            point = find_price_point(points, target)
            if not point:
                available = sorted({p["attributes"].get("customerPrice") for p in points})[:12]
                raise SystemExit(f"No {target} price point for {product_id}. Nearby: {available}")

            log(f"setting {product_id} -> ${target}")
            if DRY_RUN:
                continue

            # No attributes and no territory relationship. Adding either makes ASC
            # 409 on the price point for a pre-launch subscription; the point ID
            # already encodes the territory.
            asc.post(
                "/subscriptionPrices",
                {
                    "data": {
                        "type": "subscriptionPrices",
                        "relationships": {
                            "subscription": {"data": {"type": "subscriptions", "id": sub["id"]}},
                            "subscriptionPricePoint": {
                                "data": {"type": "subscriptionPricePoints", "id": point["id"]}
                            },
                        },
                    }
                },
            )


def set_intro_offers(asc: ASC) -> None:
    """1-week FREE_TRIAL on both subscriptions.

    Monthly gets one too: Jack optimizes for trial starts, not yearly mix, and
    monthly trials are explicitly not to be stripped.
    """
    groups = asc.get(f"/apps/{APP_ID}/subscriptionGroups", limit=20).get("data", [])
    for group in groups:
        subs = asc.get(f"/subscriptionGroups/{group['id']}/subscriptions", limit=20).get("data", [])
        for sub in subs:
            product_id = sub["attributes"].get("productId")
            if product_id not in SUB_PRICES:
                continue

            # Intro offers are per-territory, not global. One POST per territory.
            offers = asc.get_all(
                f"/subscriptions/{sub['id']}/introductoryOffers",
                limit=200,
                include="territory",
            )
            covered = set()
            for offer in offers:
                territory = (
                    (offer.get("relationships") or {}).get("territory", {}).get("data") or {}
                ).get("id")
                if territory:
                    covered.add(territory)

            territories = [t["id"] for t in asc.get_all("/territories", limit=200)]
            missing = [t for t in territories if t not in covered]
            if not missing:
                log(f"intro offer exists in all territories: {product_id}")
                continue

            log(f"creating 1-week free trial in {len(missing)} territories: {product_id}")
            if DRY_RUN:
                continue

            for territory in missing:
                asc.post(
                    "/subscriptionIntroductoryOffers",
                    {
                        "data": {
                            "type": "subscriptionIntroductoryOffers",
                            "attributes": {
                                "duration": "ONE_WEEK",
                                "offerMode": "FREE_TRIAL",
                                "numberOfPeriods": 1,
                            },
                            "relationships": {
                                "subscription": {
                                    "data": {"type": "subscriptions", "id": sub["id"]}
                                },
                                "territory": {"data": {"type": "territories", "id": territory}},
                            },
                        }
                    },
                )


def set_lifetime_price(asc: ASC) -> None:
    iaps = asc.get(f"/apps/{APP_ID}/inAppPurchasesV2", limit=20).get("data", [])
    iap = next((i for i in iaps if i["attributes"].get("productId") == LIFETIME_PRODUCT), None)
    if not iap:
        raise SystemExit(f"{LIFETIME_PRODUCT} not found; run asc-setup-iap.py first")

    schedule = asc.get_optional(f"{V2}/inAppPurchases/{iap['id']}/iapPriceSchedule")
    if schedule.get("data"):
        log(f"price already set: {LIFETIME_PRODUCT}")
        return

    points = asc.get_all(
        f"{V2}/inAppPurchases/{iap['id']}/pricePoints",
        limit=200,
        **{"filter[territory]": BASE_TERRITORY},
    )
    point = find_price_point(points, LIFETIME_PRICE)
    if not point:
        available = sorted({p["attributes"].get("customerPrice") for p in points})[:12]
        raise SystemExit(f"No {LIFETIME_PRICE} price point. Nearby: {available}")

    log(f"setting {LIFETIME_PRODUCT} -> ${LIFETIME_PRICE}")
    if DRY_RUN:
        return

    asc.post(
        "/inAppPurchasePriceSchedules",
        {
            "data": {
                "type": "inAppPurchasePriceSchedules",
                "relationships": {
                    "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap["id"]}},
                    "baseTerritory": {"data": {"type": "territories", "id": BASE_TERRITORY}},
                    "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price}"}]},
                },
            },
            "included": [
                {
                    "type": "inAppPurchasePrices",
                    "id": "${price}",
                    "attributes": {"startDate": None},
                    "relationships": {
                        "inAppPurchasePricePoint": {
                            "data": {"type": "inAppPurchasePricePoints", "id": point["id"]}
                        }
                    },
                }
            ],
        },
    )


def main() -> None:
    asc = ASC()
    set_subscription_prices(asc)
    set_intro_offers(asc)
    set_lifetime_price(asc)
    print("\nDone.")


if __name__ == "__main__":
    main()
