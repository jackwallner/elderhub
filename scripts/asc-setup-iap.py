#!/usr/bin/env python3
"""Create the Elderhub subscription group, subscriptions and lifetime IAP in ASC.

Idempotent: re-running skips anything that already exists.

    ./scripts/asc-setup-iap.py            # create
    DRY_RUN=1 ./scripts/asc-setup-iap.py  # show what would be created
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from asc_lib import ASC  # noqa: E402

APP_ID = "6796916172"
GROUP_REFERENCE_NAME = "Med List Pro"
GROUP_DISPLAY_NAME = "Elderhub Plus"
DRY_RUN = os.environ.get("DRY_RUN") == "1"

# ASC caps localization descriptions at 55 characters. Keep them under it.
MAX_DESCRIPTION = 55

# (productId, referenceName, period, customer-facing name, description)
SUBSCRIPTIONS = [
    (
        "com.jackwallner.aging.pro.monthly",
        "Pro Monthly",
        "ONE_MONTH",
        "Monthly",
        "Additional people in one care circle.",
    ),
    (
        "com.jackwallner.aging.pro.yearly",
        "Pro Yearly",
        "ONE_YEAR",
        "Yearly",
        "Additional people in one care circle.",
    ),
]

LIFETIME = (
    "com.jackwallner.aging.pro.lifetime",
    "Pro Lifetime",
    "Lifetime",
    "Additional people, with one purchase.",
)


def log(message: str) -> None:
    print(("[dry-run] " if DRY_RUN else "") + message)


def ensure_group(asc: ASC) -> str:
    for group in asc.get(f"/apps/{APP_ID}/subscriptionGroups", limit=50).get("data", []):
        if group["attributes"].get("referenceName") == GROUP_REFERENCE_NAME:
            log(f"group exists: {GROUP_REFERENCE_NAME} ({group['id']})")
            return group["id"]

    log(f"creating group: {GROUP_REFERENCE_NAME}")
    if DRY_RUN:
        return "DRYRUN_GROUP"

    created = asc.post(
        "/subscriptionGroups",
        {
            "data": {
                "type": "subscriptionGroups",
                "attributes": {"referenceName": GROUP_REFERENCE_NAME},
                "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
            }
        },
    )
    group_id = created["data"]["id"]

    # The group itself needs a display name per locale, separate from the
    # per-subscription localizations below.
    asc.post(
        "/subscriptionGroupLocalizations",
        {
            "data": {
                "type": "subscriptionGroupLocalizations",
                "attributes": {"name": GROUP_DISPLAY_NAME, "locale": "en-US"},
                "relationships": {
                    "subscriptionGroup": {
                        "data": {"type": "subscriptionGroups", "id": group_id}
                    }
                },
            }
        },
    )
    return group_id


def ensure_subscriptions(asc: ASC, group_id: str) -> None:
    existing = {}
    if not DRY_RUN:
        for sub in asc.get(f"/subscriptionGroups/{group_id}/subscriptions", limit=50).get("data", []):
            existing[sub["attributes"].get("productId")] = sub["id"]

    for product_id, reference, period, name, description in SUBSCRIPTIONS:
        assert len(description) <= MAX_DESCRIPTION, f"{product_id} description too long"

        sub_id = existing.get(product_id)
        if sub_id:
            log(f"sub exists: {product_id}")
        else:
            log(f"creating sub: {product_id} ({period})")
            if DRY_RUN:
                continue

            created = asc.post(
                "/subscriptions",
                {
                    "data": {
                        "type": "subscriptions",
                        "attributes": {
                            "name": reference,
                            "productId": product_id,
                            "subscriptionPeriod": period,
                            # Family Sharing off: this is a personal record keeper.
                            "familySharable": False,
                        },
                        "relationships": {
                            "group": {"data": {"type": "subscriptionGroups", "id": group_id}}
                        },
                    }
                },
            )
            sub_id = created["data"]["id"]

        # Separate from creation: a sub created by an earlier failed run can exist
        # with no localization at all, which blocks it from ever being submitted.
        locales = asc.get(f"/subscriptions/{sub_id}/subscriptionLocalizations", limit=20).get("data", [])
        if any(loc["attributes"].get("locale") == "en-US" for loc in locales):
            log(f"  localization exists: {product_id}")
            continue

        asc.post(
            "/subscriptionLocalizations",
            {
                "data": {
                    "type": "subscriptionLocalizations",
                    "attributes": {"name": name, "description": description, "locale": "en-US"},
                    "relationships": {
                        "subscription": {"data": {"type": "subscriptions", "id": sub_id}}
                    },
                }
            },
        )
        log(f"  localized {product_id}")


def ensure_lifetime(asc: ASC) -> None:
    product_id, reference, name, description = LIFETIME
    assert len(description) <= MAX_DESCRIPTION, f"{product_id} description too long"

    iap_id = None
    for iap in asc.get(f"/apps/{APP_ID}/inAppPurchasesV2", limit=50).get("data", []):
        if iap["attributes"].get("productId") == product_id:
            log(f"iap exists: {product_id}")
            iap_id = iap["id"]
            break

    if iap_id:
        locales = asc.get(f"/inAppPurchases/{iap_id}/inAppPurchaseLocalizations", limit=20).get("data", [])
        if any(loc["attributes"].get("locale") == "en-US" for loc in locales):
            log(f"  localization exists: {product_id}")
            return
        _localize_iap(asc, iap_id, name, description)
        log(f"  localized {product_id}")
        return

    log(f"creating iap: {product_id} (NON_CONSUMABLE)")
    if DRY_RUN:
        return

    # Creation lives on the /v2/ API, not /v1/. The /v1/inAppPurchases collection
    # is read-only and /v1/inAppPurchasesV2 is only a relationship path off an app.
    created = asc.post(
        "https://api.appstoreconnect.apple.com/v2/inAppPurchases",
        {
            "data": {
                "type": "inAppPurchases",
                "attributes": {
                    "name": reference,
                    "productId": product_id,
                    "inAppPurchaseType": "NON_CONSUMABLE",
                    "familySharable": False,
                },
                "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
            }
        },
    )
    iap_id = created["data"]["id"]
    _localize_iap(asc, iap_id, name, description)
    log(f"  localized {product_id}")


def _localize_iap(asc: ASC, iap_id: str, name: str, description: str) -> None:
    asc.post(
        "/inAppPurchaseLocalizations",
        {
            "data": {
                "type": "inAppPurchaseLocalizations",
                "attributes": {"name": name, "description": description, "locale": "en-US"},
                "relationships": {
                    "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}
                },
            }
        },
    )


def main() -> None:
    asc = ASC()
    group_id = ensure_group(asc)
    ensure_subscriptions(asc, group_id)
    ensure_lifetime(asc)
    print("\nDone. Prices are NOT set here; run asc-set-iap-prices.py next.")


if __name__ == "__main__":
    main()
