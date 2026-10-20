#!/usr/bin/env python3
"""Create or update Elderhub's Google Play products (Android Publisher API).

Elderhub Plus monthly and yearly subscriptions (one base plan each, with a 7-day
free trial offer for new customers) and the lifetime one-time product, at the
Android US price ladder. Local prices come from Play's own conversion of the
US price. Idempotent: existing products are left alone unless --update.

    python3 scripts/play-products.py --plan          # offline, no credentials
    PLAY_SERVICE_ACCOUNT_JSON=... python3 scripts/play-products.py [--dry-run]
"""
import json
import os
import sys

try:
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    from googleapiclient.errors import HttpError
except ImportError:  # --plan runs without the Google client libraries
    service_account = build = HttpError = None

PACKAGE = "com.jackwallner.aging"
REGIONS_VERSION = "2025/03"
# Proposed Android ladder: about 20% under iOS ($9.99 / $39.99 / $89.99, Aging/Services/Products.storekit),
# matching the fleet rule. Not yet approved by Jack; see .claude/rules/android.md before running.
SUBSCRIPTIONS = [
    ("com.jackwallner.aging.pro.monthly", "monthly", "P1M", ("7", 990_000_000), "Elderhub Plus Monthly"),
    ("com.jackwallner.aging.pro.yearly", "yearly", "P1Y", ("31", 990_000_000), "Elderhub Plus Yearly"),
]
LIFETIME = ("com.jackwallner.aging.pro.lifetime", ("71", 990_000_000), "Elderhub Plus Lifetime")
DESCRIPTION = "Care records for everyone you look after: add a second parent, a partner, or anyone else."


# The fleet's PPP curve (~/ios/pricing/refratio.json, KOR excluded as an
# equalization artifact), applied on top of Play's exchange-rate conversion so
# Android prices track the iOS discounts in the same markets.
PPP = {
    "EG": 0.38, "ID": 0.38, "IN": 0.38, "NG": 0.38, "PK": 0.38, "PH": 0.38, "TR": 0.38, "VN": 0.38,
    "BR": 0.40, "CL": 0.40, "HU": 0.41, "PL": 0.45, "RO": 0.45, "CO": 0.47, "ZA": 0.48, "MY": 0.51,
    "RU": 0.53, "MX": 0.55, "TH": 0.55, "CZ": 0.68, "AE": 0.73, "SA": 0.73, "CN": 0.87,
}


def discounted(region, price):
    """Scale a converted local price by the PPP ratio and round to a local .99 or ...9 ending."""
    ratio = PPP.get(region)
    if not ratio:
        return price
    value = (int(price["units"]) + price.get("nanos", 0) / 1e9) * ratio
    if price.get("nanos", 0) == 0 and int(price["units"]) >= 100:
        step = 10 ** max(1, len(str(int(value))) - 2)
        target = max(step, round(value / step) * step) - 1
        return {"currencyCode": price["currencyCode"], "units": str(int(target)), "nanos": 0}
    whole = max(0, int(value))
    return {"currencyCode": price["currencyCode"], "units": str(whole), "nanos": 990_000_000}


def money(units_nanos, currency="USD"):
    units, nanos = units_nanos
    return {"currencyCode": currency, "units": units, "nanos": nanos}


def service():
    creds = service_account.Credentials.from_service_account_file(
        os.environ["PLAY_SERVICE_ACCOUNT_JSON"], scopes=["https://www.googleapis.com/auth/androidpublisher"])
    return build("androidpublisher", "v3", credentials=creds, cache_discovery=False)


def converted(api, price):
    result = api.monetization().convertRegionPrices(packageName=PACKAGE, body={"price": money(price)}).execute()
    regions = result["convertedRegionPrices"]
    for code, value in regions.items():
        value["price"] = discounted(code, value["price"])
    return regions, result.get("convertedOtherRegionsPrice", {})


def subscription_body(product_id, plan_id, period, price, title, api):
    regions, other = converted(api, price)
    regional = [{"regionCode": code, "price": value["price"], "newSubscriberAvailability": True} for code, value in sorted(regions.items())]
    body = {
        "packageName": PACKAGE,
        "productId": product_id,
        "listings": [{"languageCode": "en-US", "title": title, "description": DESCRIPTION, "benefits": [
            "Add more people", "Every care feature for each person"]}],
        "basePlans": [{
            "basePlanId": plan_id,
            "autoRenewingBasePlanType": {"billingPeriodDuration": period, "resubscribeState": "RESUBSCRIBE_STATE_ACTIVE",
                                         "prorationMode": "SUBSCRIPTION_PRORATION_MODE_CHARGE_ON_NEXT_BILLING_DATE",
                                         "legacyCompatible": True, "legacyCompatibleSubscriptionOfferId": ""},
            "regionalConfigs": regional,
            "otherRegionsConfig": {"usdPrice": other.get("usdPrice"), "eurPrice": other.get("eurPrice"), "newSubscriberAvailability": True}
            if other else None,
        }],
    }
    if body["basePlans"][0]["otherRegionsConfig"] is None:
        del body["basePlans"][0]["otherRegionsConfig"]
    return body, [code for code in regions]


def create_with_currency_fixes(call, configs, base_price):
    """Some regions bill in USD on Play even though conversion returns local currency (AR, for one).
    Retry, repricing each region Play rejects in USD at the US price (PPP-scaled when it applies)."""
    import re
    for _ in range(80):
        try:
            return call()
        except HttpError as error:
            unbillable = re.search(r"Region code (\w+) is not billable", str(error))
            if unbillable:
                for group in (configs if configs and isinstance(configs[0], list) else [configs]):
                    group[:] = [c for c in group if c.get("regionCode") != unbillable.group(1)]
                print(f"  {unbillable.group(1)}: not billable, skipped")
                continue
            match = re.search(r"region code (\w+) .*Expected (\w+) but got (\w+)", str(error))
            if not match or match.group(2) != "USD":
                raise
            region = match.group(1)
            usd = discounted(region, money(base_price))
            for config in configs:
                key = "price"
                if config.get("regionCode") == region:
                    config[key] = usd
            print(f"  {region}: priced in USD {usd['units']}.{str(usd['nanos'])[:2]}")
    raise RuntimeError("too many currency fixes")


def ensure_subscription(api, spec, dry):
    product_id, plan_id, period, price, title = spec
    subs = api.monetization().subscriptions()
    try:
        existing = subs.get(packageName=PACKAGE, productId=product_id).execute()
        print(f"exists: {product_id} ({[b['state'] for b in existing.get('basePlans', [])]})")
    except HttpError as error:
        if error.resp.status != 404:
            raise
        body, regions = subscription_body(product_id, plan_id, period, price, title, api)
        print(f"create: {product_id} base plan {plan_id} {period} in {len(regions)} regions")
        if dry:
            return
        create_with_currency_fixes(
            lambda: subs.create(packageName=PACKAGE, productId=product_id, body=body, regionsVersion_version=REGIONS_VERSION).execute(),
            body["basePlans"][0]["regionalConfigs"], price)
    if dry:
        return
    plans = subs.basePlans()
    current = subs.get(packageName=PACKAGE, productId=product_id).execute()
    if current["basePlans"][0]["state"] != "ACTIVE":
        plans.activate(packageName=PACKAGE, productId=product_id, basePlanId=plan_id, body={}).execute()
        print(f"  activated base plan {plan_id}")
    offers = plans.offers()
    try:
        offer = offers.get(packageName=PACKAGE, productId=product_id, basePlanId=plan_id, offerId="trial-7d").execute()
    except HttpError as error:
        if error.resp.status != 404:
            raise
        regions = [c["regionCode"] for c in current["basePlans"][0]["regionalConfigs"]]
        body = {
            "packageName": PACKAGE, "productId": product_id, "basePlanId": plan_id, "offerId": "trial-7d",
            "phases": [{"recurrenceCount": 1, "duration": "P1W",
                        "regionalConfigs": [{"regionCode": code, "free": {}} for code in regions],
                        "otherRegionsConfig": {"free": {}}}],
            "targeting": {"acquisitionRule": {"scope": {"thisSubscription": {}}}},
            "regionalConfigs": [{"regionCode": code, "newSubscriberAvailability": True} for code in regions],
            "otherRegionsConfig": {"otherRegionsNewSubscriberAvailability": True},
            "offerTags": [{"tag": "trial"}],
        }
        offer = create_with_currency_fixes(
            lambda: offers.create(packageName=PACKAGE, productId=product_id, basePlanId=plan_id, offerId="trial-7d",
                                  body=body, regionsVersion_version=REGIONS_VERSION).execute(),
            [body["phases"][0]["regionalConfigs"], body["regionalConfigs"]], price)
        print("  created offer trial-7d")
    if offer.get("state") != "ACTIVE":
        offers.activate(packageName=PACKAGE, productId=product_id, basePlanId=plan_id, offerId="trial-7d", body={}).execute()
        print("  activated offer trial-7d")


def ensure_lifetime(api, dry):
    """The one-time product, on the new one-time products API with a `lifetime` buy option."""
    product_id, price, title = LIFETIME
    products = api.monetization().onetimeproducts()
    try:
        existing = products.get(packageName=PACKAGE, productId=product_id).execute()
        print(f"exists: {product_id} ({[o.get('state') for o in existing.get('purchaseOptions', [])]})")
    except HttpError as error:
        if error.resp.status != 404:
            raise
        regions, other = converted(api, price)
        body = {
            "packageName": PACKAGE,
            "productId": product_id,
            "listings": [{"languageCode": "en-US", "title": title, "description": DESCRIPTION}],
            "purchaseOptions": [{
                "purchaseOptionId": "lifetime",
                "buyOption": {"legacyCompatible": True, "multiQuantityEnabled": False},
                "regionalPricingAndAvailabilityConfigs": [
                    {"regionCode": code, "price": value["price"], "availability": "AVAILABLE"} for code, value in sorted(regions.items())
                ],
            }],
        }
        print(f"create: {product_id} buy option lifetime in {len(regions)} regions")
        if dry:
            return
        create_with_currency_fixes(
            lambda: products.patch(packageName=PACKAGE, productId=product_id, body=body, allowMissing=True,
                                   updateMask="listings,purchaseOptions", regionsVersion_version=REGIONS_VERSION).execute(),
            body["purchaseOptions"][0]["regionalPricingAndAvailabilityConfigs"], price)
    if dry:
        return
    products.purchaseOptions().batchUpdateStates(packageName=PACKAGE, productId=product_id, body={"requests": [
        {"activatePurchaseOptionRequest": {"packageName": PACKAGE, "productId": product_id, "purchaseOptionId": "lifetime"}}
    ]}).execute()
    print("  activated buy option lifetime")


def plan():
    """Offline: print the US ladder and ids without credentials or API calls."""
    for product_id, plan_id, period, (units, nanos), title in SUBSCRIPTIONS:
        print(f"{product_id}:{plan_id} {period} ${units}.{nanos // 10_000_000:02d} 7-day free trial (new customers) {title}")
    product_id, (units, nanos), title = LIFETIME
    print(f"{product_id} one-time ${units}.{nanos // 10_000_000:02d} {title}")


def main():
    if "--plan" in sys.argv:
        plan()
        return
    dry = "--dry-run" in sys.argv
    api = service()
    for spec in SUBSCRIPTIONS:
        ensure_subscription(api, spec, dry)
    ensure_lifetime(api, dry)


if __name__ == "__main__":
    main()
