#!/usr/bin/env python3
"""Attach a paywall review screenshot to every Elderhub IAP.

Subscriptions and non-consumables sit at MISSING_METADATA until they have one,
and MISSING_METADATA products are not served to StoreKit.

Produce the screenshot with the StoreKit-Testing UI test, not `simctl`:

    OWNER=aging
    UDID=$(agent-sim checkout "$OWNER")
    trap 'agent-sim checkin "$OWNER"' EXIT
    agent-sim boot "$OWNER"
    xcodebuild -project Aging.xcodeproj -scheme Aging \\
      -destination "id=$UDID" \\
      -resultBundlePath build/xcresult -only-testing:AgingUITests test
    xcrun xcresulttool export attachments --path build/xcresult.xcresult \\
      --output-path /tmp/paywall

    ./scripts/asc-upload-iap-screenshot.py /tmp/paywall/<the>.png
"""

import hashlib
import os
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from asc_lib import ASC  # noqa: E402

APP_ID = "6796916172"
V2 = "https://api.appstoreconnect.apple.com/v2"


def upload_bytes(operations: list[dict], payload: bytes) -> None:
    for op in operations:
        chunk = payload[op["offset"] : op["offset"] + op["length"]]
        request = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for header in op.get("requestHeaders", []):
            request.add_header(header["name"], header["value"])
        with urllib.request.urlopen(request) as response:
            if response.status not in (200, 201):
                raise SystemExit(f"chunk upload failed: {response.status}")


def attach(asc: ASC, collection: str, relationship_key: str, relationship_type: str,
           resource_id: str, path: Path, label: str) -> None:
    payload = path.read_bytes()
    created = asc.post(
        f"/{collection}",
        {
            "data": {
                "type": collection,
                "attributes": {"fileSize": len(payload), "fileName": path.name},
                "relationships": {
                    relationship_key: {"data": {"type": relationship_type, "id": resource_id}}
                },
            }
        },
    )
    screenshot_id = created["data"]["id"]
    upload_bytes(created["data"]["attributes"]["uploadOperations"], payload)

    asc.patch(
        f"/{collection}/{screenshot_id}",
        {
            "data": {
                "type": collection,
                "id": screenshot_id,
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": hashlib.md5(payload).hexdigest(),
                },
            }
        },
    )
    print(f"  attached to {label}")


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    path = Path(sys.argv[1])
    if not path.exists():
        raise SystemExit(f"not found: {path}")

    asc = ASC()

    for group in asc.get(f"/apps/{APP_ID}/subscriptionGroups", limit=20).get("data", []):
        for sub in asc.get(f"/subscriptionGroups/{group['id']}/subscriptions", limit=20).get("data", []):
            product_id = sub["attributes"]["productId"]
            existing = asc.get_optional(f"/subscriptions/{sub['id']}/appStoreReviewScreenshot")
            if existing.get("data"):
                print(f"  screenshot exists: {product_id}")
                continue
            attach(
                asc,
                "subscriptionAppStoreReviewScreenshots",
                "subscription",
                "subscriptions",
                sub["id"],
                path,
                product_id,
            )

    for iap in asc.get(f"/apps/{APP_ID}/inAppPurchasesV2", limit=20).get("data", []):
        product_id = iap["attributes"]["productId"]
        existing = asc.get_optional(f"{V2}/inAppPurchases/{iap['id']}/appStoreReviewScreenshot")
        if existing.get("data"):
            print(f"  screenshot exists: {product_id}")
            continue
        attach(
            asc,
            "inAppPurchaseAppStoreReviewScreenshots",
            "inAppPurchaseV2",
            "inAppPurchases",
            iap["id"],
            path,
            product_id,
        )

    print("\nDone.")


if __name__ == "__main__":
    main()
