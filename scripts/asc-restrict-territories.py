#!/usr/bin/env python3
"""Remove Elderhub from EU and UK storefronts (D33).

Needs a Python newer than the system 3.9, because asc_lib uses `X | None`
annotations. `/opt/homebrew/bin/python3.14 scripts/asc-restrict-territories.py`.

Why this exists: the app holds Article 9 special-category health data about
third parties who never consented to a data controller they have never heard of,
and it would carry DSR and Article 27 representative obligations that a solo
developer cannot actually run. So the app is not offered there. That is a
deliberate revenue trade, recorded in docs/architecture.md §13 Q3.

Territory availability applies to the *app*, not to a version, so this also
removes any build already out there from those storefronts. It is reversible:
`--restore` puts back exactly what `--backup` saved.

    ./scripts/asc-restrict-territories.py --dry-run
    ./scripts/asc-restrict-territories.py --backup territories.json
    ./scripts/asc-restrict-territories.py --apply --backup territories.json
    ./scripts/asc-restrict-territories.py --restore territories.json
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from asc_lib import ASC  # noqa: E402

BUNDLE_ID = "com.jackwallner.aging"

# EEA (the 27 EU member states plus Iceland, Liechtenstein, Norway) and the UK.
# Gibraltar is included: UK GDPR applies there.
EXCLUDED = {
    # EU 27
    "AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN", "FRA",
    "DEU", "GRC", "HUN", "IRL", "ITA", "LVA", "LTU", "LUX", "MLT", "NLD",
    "POL", "PRT", "ROU", "SVK", "SVN", "ESP", "SWE",
    # EEA non-EU
    "ISL", "LIE", "NOR",
    # UK and its GDPR footprint
    "GBR", "GIB",
}


def find_app(asc: ASC) -> dict:
    for app in asc.apps():
        if app["attributes"].get("bundleId") == BUNDLE_ID:
            return app
    raise SystemExit(f"No app on ASC with bundle id {BUNDLE_ID}")


def availability_id(asc: ASC, app_id: str) -> str | None:
    """The app's availability record, which is a to-one relationship.

    Returns None for an app that has never been configured for sale. That is not
    an error: territory availability does not exist until the app has a first
    release set up in App Store Connect, and there is nothing to restrict yet.
    """
    response = asc.get_optional(f"/apps/{app_id}/appAvailabilityV2")
    return (response.get("data") or {}).get("id")


def current_availability(asc: ASC, availability: str) -> list[dict]:
    """Every territory row, available or not.

    The collection is a **v2** path while the individual rows are patched on
    v1, which is not a typo. asc_lib defaults to v1, so this one is absolute.
    A full territory list is around 175 rows, so it pages.
    """
    return asc.get_all(
        f"https://api.appstoreconnect.apple.com/v2/appAvailabilities/{availability}"
        "/territoryAvailabilities",
        limit=200,
        include="territory",
    )


def territory_code(row: dict) -> str:
    return (row.get("relationships", {}).get("territory", {}).get("data") or {}).get("id", "")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="actually write")
    parser.add_argument("--dry-run", action="store_true", help="show what would change")
    parser.add_argument("--backup", type=Path, help="write the current state here first")
    parser.add_argument("--restore", type=Path, help="put a saved state back")
    args = parser.parse_args()

    asc = ASC()
    app = find_app(asc)
    app_id = app["id"]
    print(f"==> {app['attributes'].get('name')} ({app_id})")

    availability = availability_id(asc, app_id)
    if availability is None:
        print("    no availability record yet: the app has never been configured")
        print("    for sale, so there is nothing to restrict. Re-run once the")
        print("    first release is set up in App Store Connect.")
        return

    rows = current_availability(asc, availability)
    state = {territory_code(row): row["attributes"].get("available", False) for row in rows}
    by_code = {territory_code(row): row["id"] for row in rows}

    if args.restore:
        wanted = json.loads(args.restore.read_text())
        changes = {code: value for code, value in wanted.items()
                   if state.get(code) != value and code in by_code}
    else:
        changes = {code: False for code in EXCLUDED
                   if state.get(code) and code in by_code}

    if args.backup:
        args.backup.write_text(json.dumps(state, indent=2, sort_keys=True))
        print(f"    backed up {len(state)} territories to {args.backup}")

    if not changes:
        print("    nothing to change")
        return

    print(f"    {len(changes)} territories to change:")
    for code in sorted(changes):
        print(f"      {code}: {state.get(code)} -> {changes[code]}")

    if not args.apply:
        print("\n    dry run. Re-run with --apply to write.")
        return

    # One PATCH per territory row. There is no batch endpoint, and doing it row
    # by row means a throttle partway through leaves a knowable state rather
    # than an ambiguous one.
    for code in sorted(changes):
        asc.patch(
            f"/territoryAvailabilities/{by_code[code]}",
            {
                "data": {
                    "type": "territoryAvailabilities",
                    "id": by_code[code],
                    "attributes": {"available": changes[code]},
                }
            },
        )
        print(f"      {code} set to {changes[code]}")

    print("==> done")


if __name__ == "__main__":
    main()
