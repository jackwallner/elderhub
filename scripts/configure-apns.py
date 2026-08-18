#!/usr/bin/env python3
"""Point the escalation function at an APNs auth key, and prove it works.

    ./scripts/configure-apns.py ~/Downloads/AuthKey_ABCD123456.p8

That is the whole job. The key id is read from the filename, which is how Apple
names the download; pass --key-id to override.

Why this exists rather than a line of documentation. The obvious command,

    supabase secrets set APNS_PRIVATE_KEY="$(cat AuthKey_XXXX.p8)"

has two failure modes and neither of them says anything. The PEM is multi-line,
and a newline that does not survive the CLI produces a secret that is present,
wrong, and only complains at 3am when a push is actually due. And an App Store
Connect API key is byte-for-byte the same kind of file as an APNs key, so
reaching for the wrong .p8 in ~/.private_keys is easy and silent: Apple answers
403 InvalidProviderToken, which nobody sees until the first missed check-in.

So this checks the key against Apple *before* it writes anything, sends the PEM
with its newlines escaped the way the function unescapes them
(SupabaseFunctions/escalate-check-ins/index.ts), and then calls the function to
confirm the whole path is live. It never prints the key.

Needs a Python newer than the system 3.9.
"""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.serialization import load_pem_private_key

TEAM_ID = "YXG4MP6W39"
BUNDLE_ID = "com.jackwallner.aging"
CREDENTIALS = Path.home() / ".aging_credentials"

# An all-zero token is well formed and belongs to nobody, so Apple has to check
# the provider token before it can tell us the device is wrong. That ordering is
# the whole trick: BadDeviceToken means the signature was accepted.
DEAD_TOKEN = "0" * 64


def credentials() -> dict[str, str]:
    """Read ~/.aging_credentials without sourcing it into this process."""
    values: dict[str, str] = {}
    for line in CREDENTIALS.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        line = line.removeprefix("export ").strip()
        if "=" not in line:
            continue
        name, _, value = line.partition("=")
        values[name.strip()] = value.strip().strip('"').strip("'")
    return values


def key_id_from(path: Path, override: str | None) -> str:
    if override:
        return override
    match = re.fullmatch(r"AuthKey_([A-Z0-9]{10})", path.stem)
    if not match:
        raise SystemExit(
            f"Cannot read a key id out of {path.name}. Apple names the download "
            "AuthKey_XXXXXXXXXX.p8; pass --key-id if this one was renamed."
        )
    return match.group(1)


def provider_token(key_id: str, pem: bytes) -> str:
    """The same ES256 JWT the edge function mints, built the same way."""
    try:
        key = load_pem_private_key(pem, password=None)
    except Exception as error:
        raise SystemExit(f"That file is not a PEM private key: {error}")
    if not isinstance(key, ec.EllipticCurvePrivateKey):
        raise SystemExit("An APNs key is an EC P-256 key; this one is not.")

    def segment(payload: dict) -> bytes:
        return base64.urlsafe_b64encode(json.dumps(payload).encode()).rstrip(b"=")

    signing_input = (
        segment({"alg": "ES256", "kid": key_id})
        + b"."
        + segment({"iss": TEAM_ID, "iat": int(time.time())})
    )
    r, s = decode_dss_signature(key.sign(signing_input, ec.ECDSA(hashes.SHA256())))
    signature = base64.urlsafe_b64encode(
        r.to_bytes(32, "big") + s.to_bytes(32, "big")
    ).rstrip(b"=")
    return (signing_input + b"." + signature).decode()


def check_against_apple(key_id: str, pem: bytes) -> None:
    """Refuse to store a key Apple will not accept.

    Exits with the reason rather than a status code, because the two failures
    that actually happen (wrong .p8, key revoked) look identical from here
    otherwise.
    """
    # curl, not urllib: APNs speaks HTTP/2 only and the standard library does
    # not, so urllib gets a protocol error rather than an answer from Apple.
    result = subprocess.run(
        [
            "curl", "--silent", "--show-error", "--http2", "--max-time", "30",
            "--write-out", "\n%{http_code}",
            "--header", f"authorization: bearer {provider_token(key_id, pem)}",
            "--header", f"apns-topic: {BUNDLE_ID}",
            "--header", "apns-push-type: alert",
            "--header", "content-type: application/json",
            "--data", json.dumps({"aps": {"alert": "connectivity check"}}),
            f"https://api.push.apple.com/3/device/{DEAD_TOKEN}",
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise SystemExit(f"Could not reach Apple: {result.stderr.strip()}. Nothing was written.")

    body, _, status = result.stdout.rpartition("\n")
    if status.strip() == "200":
        # A 200 for a token of all zeroes should be impossible, but a key that
        # somehow got a push delivered is a key that works.
        print("    Apple accepted the key")
        return
    try:
        reason = json.loads(body).get("reason", "")
    except json.JSONDecodeError:
        reason = body.strip()[:200]

    if reason == "BadDeviceToken":
        # Apple validated the signature and then rejected the device. That is
        # exactly as far as this check can get, and it is far enough.
        print(f"    Apple accepted key {key_id} for {BUNDLE_ID}")
        return
    if reason == "InvalidProviderToken":
        raise SystemExit(
            f"Apple rejected key {key_id}: InvalidProviderToken.\n"
            "  Almost always the wrong .p8. An App Store Connect API key looks\n"
            "  identical and is not one of these: the key has to be created under\n"
            "  Certificates, Identifiers & Profiles with Apple Push Notifications\n"
            "  service ticked. Nothing was written."
        )
    if reason == "TopicDisallowed":
        raise SystemExit(
            f"Apple rejected the topic {BUNDLE_ID} for key {key_id}. The key is\n"
            "  real but is not enabled for this app's team. Nothing was written."
        )
    raise SystemExit(f"Apple rejected the key: {reason or 'no reason given'}. Nothing was written.")


def escaped(pem: bytes) -> str:
    """Newlines as a literal backslash-n, which is what the function unescapes.

    A real newline inside a secret is the failure this whole script exists to
    avoid: it survives some transports and not others, and the difference is
    invisible until a push is due.
    """
    return pem.decode().replace("\r\n", "\n").replace("\n", "\\n")


def run(command: list[str], env: dict[str, str], quiet_arg_count: int = 0) -> str:
    printable = command[: len(command) - quiet_arg_count]
    if quiet_arg_count:
        printable = printable + ["<redacted>"] * quiet_arg_count
    print(f"    $ {' '.join(printable)}")
    result = subprocess.run(command, env=env, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"    failed: {result.stderr.strip() or result.stdout.strip()}")
    return result.stdout


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("p8", type=Path, help="the AuthKey_XXXXXXXXXX.p8 Apple gave you")
    parser.add_argument("--key-id", help="override the key id read from the filename")
    parser.add_argument("--check-only", action="store_true",
                        help="test the key against Apple and write nothing")
    args = parser.parse_args()

    if not args.p8.is_file():
        raise SystemExit(f"No such file: {args.p8}")

    key_id = key_id_from(args.p8, args.key_id)
    pem = args.p8.read_bytes()

    print(f"==> checking {args.p8.name} against APNs")
    check_against_apple(key_id, pem)
    if args.check_only:
        print("==> check only, nothing written")
        return

    creds = credentials()
    ref = creds.get("AGING_SUPABASE_PROJECT_REF", "oygrxltpydcmmdtbreec")
    env = dict(os.environ, SUPABASE_ACCESS_TOKEN=creds["AGING_SUPABASE_ACCESS_TOKEN"])

    print(f"==> setting secrets on {ref}")
    run(
        ["supabase", "secrets", "set", "--project-ref", ref,
         f"APNS_KEY_ID={key_id}", f"APNS_PRIVATE_KEY={escaped(pem)}"],
        env,
        quiet_arg_count=1,
    )

    # The CLI answers a bare list with --output json and an object with the
    # plain text formatter. Accept either rather than depending on the version.
    listed = json.loads(run(["supabase", "secrets", "list", "--project-ref", ref,
                             "--output", "json"], env))
    rows = listed.get("secrets", []) if isinstance(listed, dict) else listed
    present = {secret["name"] for secret in rows}
    required = {"APNS_KEY_ID", "APNS_TEAM_ID", "APNS_BUNDLE_ID", "APNS_PRIVATE_KEY"}
    if missing := sorted(required - present):
        raise SystemExit(f"    still missing: {', '.join(missing)}")
    print(f"    all four APNs secrets are set")

    # The function reads its environment once per isolate, so a run started
    # before the secrets landed can still answer 503. Give it a moment.
    print("==> calling the function")
    time.sleep(5)
    request = urllib.request.Request(
        f"https://{ref}.supabase.co/functions/v1/escalate-check-ins",
        method="POST",
        data=b"{}",
        headers={
            # Capital B: the Supabase gateway rejects a lowercase scheme, unlike
            # APNs above, which wants it lowercase.
            "authorization": f"Bearer {creds['AGING_SUPABASE_SERVICE_ROLE_KEY']}",
            "content-type": "application/json",
        },
    )
    try:
        body = json.loads(urllib.request.urlopen(request, timeout=60).read())
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise SystemExit(f"    function returned {error.code}: {detail}")

    print(f"    {json.dumps(body)}")
    print("==> done. Escalation pushes are live.")


if __name__ == "__main__":
    main()
