#!/usr/bin/env python3
"""Assert that every column the client sends actually exists in production.

plan84 §1.1 was this, undetected for two builds: `MedicationDTO` grew six
columns from migrations 0009-0011, those migrations were written, tested and
never applied to the live project, and PostgREST answers an upsert carrying an
unknown column with PGRST204. Nothing anywhere compared the two, so the
mismatch was invisible until someone dumped `information_schema` by hand.

The DTOs are the contract. This reads them out of the Swift source rather than
duplicating them here, so a field added to a DTO is checked the moment it is
added and there is no second list to keep in step.

    ./scripts/check-schema-drift.py            # check production
    ./scripts/check-schema-drift.py --verbose  # list every field checked

Exits non-zero on the first table that disagrees. Meant for the ship script,
where it costs one round trip and saves a build.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# The DTOs and the `SyncEntity` catalogue live in different files.
DTO_SOURCE = ROOT / "Shared" / "Services" / "SyncRemote.swift"
ENTITY_SOURCE = ROOT / "Shared" / "Models" / "SyncModels.swift"
DB_APPLY = ROOT / "scripts" / "db-apply.sh"

# `check_in_settings` rows are written by the client but `id` is not a column:
# the table is keyed on the recipient. The DTO models that with a computed
# `id`, which the parser already skips, so nothing special is needed here.
# Columns the server owns and the client never sends are fine and expected;
# only the other direction is a defect.


def entity_tables(source: str) -> dict[str, str]:
    """Map `SyncEntity` case names to their table names."""
    block = re.search(r"enum SyncEntity[^{]*\{(.*?)\n\}", source, re.S)
    if not block:
        sys.exit("could not find `enum SyncEntity` in SyncModels.swift")
    return dict(re.findall(r'case\s+(\w+)\s*=\s*"([^"]+)"', block.group(1)))


def dto_fields(source: str) -> dict[str, list[str]]:
    """Map each DTO's entity case name to the stored properties it encodes."""
    result: dict[str, list[str]] = {}
    for match in re.finditer(r"struct\s+(\w+DTO):\s*SyncDTO\s*\{(.*?)\n\}", source, re.S):
        name, body = match.group(1), match.group(2)

        entity = re.search(r"static\s+(?:let|var)\s+entity\s*=\s*SyncEntity\.(\w+)", body)
        if not entity:
            sys.exit(f"{name} has no `static let entity`")

        fields = []
        for line in body.splitlines():
            stripped = line.strip()
            # Stored properties only. A computed property (`var id: UUID { ... }`)
            # is not synthesized into the Codable payload and is never sent.
            prop = re.match(r"var\s+(\w+)\s*:\s*[^={]+$", stripped)
            if prop:
                fields.append(prop.group(1))
        result[entity.group(1)] = fields
    return result


def live_columns(table: str) -> set[str]:
    sql = (
        "select column_name from information_schema.columns "
        f"where table_schema='public' and table_name='{table}';"
    )
    out = subprocess.run(
        [str(DB_APPLY), "--sql", sql], capture_output=True, text=True, check=True
    ).stdout
    try:
        rows = json.loads(out)
    except json.JSONDecodeError:
        sys.exit(f"could not read columns for {table}: {out.strip()}")
    if not isinstance(rows, list):
        sys.exit(f"could not read columns for {table}: {out.strip()}")
    return {row["column_name"] for row in rows}


def main() -> int:
    verbose = "--verbose" in sys.argv
    tables = entity_tables(ENTITY_SOURCE.read_text())
    dtos = dto_fields(DTO_SOURCE.read_text())

    if not dtos:
        sys.exit(f"parsed no DTOs out of {DTO_SOURCE.name}; the check would pass vacuously")
    if len(dtos) != len(tables):
        sys.exit(
            f"{len(tables)} sync entities but {len(dtos)} DTOs parsed; "
            "an entity would go unchecked"
        )

    failures: list[str] = []

    for entity, fields in sorted(dtos.items()):
        table = tables.get(entity)
        if table is None:
            failures.append(f"{entity}: no table mapped in SyncEntity")
            continue

        columns = live_columns(table)
        if not columns:
            failures.append(f"{table}: table does not exist in production")
            continue

        missing = sorted(set(fields) - columns)
        if missing:
            failures.append(f"{table}: client sends columns that do not exist: {', '.join(missing)}")
        elif verbose:
            print(f"  ok {table} ({len(fields)} fields)")
        else:
            print(f"  ok {table}")

    if failures:
        print("\nSchema drift:", file=sys.stderr)
        for failure in failures:
            print(f"  FAIL {failure}", file=sys.stderr)
        print(
            "\nRun ./scripts/db-apply.sh to apply pending migrations, "
            "then re-run this check.",
            file=sys.stderr,
        )
        return 1

    print("==> no schema drift")
    return 0


if __name__ == "__main__":
    sys.exit(main())
