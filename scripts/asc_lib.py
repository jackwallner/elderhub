"""Minimal App Store Connect API client.

Reads credentials from ~/.baseball_credentials (ASC_API_KEY_ID, ASC_ISSUER_ID,
ASC_KEY_PATH), which is shared across the fleet.
"""

import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import jwt

BASE = "https://api.appstoreconnect.apple.com/v1"


def _load_credentials() -> tuple[str, str, str]:
    env_path = Path.home() / ".baseball_credentials"
    values: dict[str, str] = {}
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            match = re.match(r'^\s*(?:export\s+)?([A-Z_]+)=["\']?([^"\'#]*)["\']?', line)
            if match:
                values[match.group(1)] = match.group(2).strip()

    key_id = os.environ.get("ASC_API_KEY_ID") or values.get("ASC_API_KEY_ID", "")
    issuer_id = os.environ.get("ASC_ISSUER_ID") or values.get("ASC_ISSUER_ID", "")
    # The credentials file stores the key path with a literal $HOME.
    key_path = os.environ.get("ASC_KEY_PATH") or values.get("ASC_KEY_PATH", "")
    key_path = os.path.expandvars(key_path)

    if not (key_id and issuer_id and key_path):
        raise SystemExit("Missing ASC_API_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH")

    return key_id, issuer_id, key_path


class ASC:
    def __init__(self) -> None:
        key_id, issuer_id, key_path = _load_credentials()
        private_key = Path(key_path).expanduser().read_text()
        now = int(time.time())
        self.token = jwt.encode(
            {"iss": issuer_id, "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"},
            private_key,
            algorithm="ES256",
            headers={"kid": key_id, "typ": "JWT"},
        )

    def _request(self, method: str, path: str, payload: dict | None = None) -> dict:
        url = path if path.startswith("http") else f"{BASE}{path}"
        data = json.dumps(payload).encode() if payload is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Authorization", f"Bearer {self.token}")
        if data:
            request.add_header("Content-Type", "application/json")

        try:
            with urllib.request.urlopen(request) as response:
                body = response.read()
                return json.loads(body) if body else {}
        except urllib.error.HTTPError as error:
            detail = error.read().decode()
            raise SystemExit(f"{method} {url} -> {error.code}\n{detail}") from error

    def get(self, path: str, **params) -> dict:
        if params:
            path = f"{path}?{urllib.parse.urlencode(params)}"
        return self._request("GET", path)

    def get_optional(self, path: str, **params) -> dict:
        """GET that treats 404 as an empty result.

        ASC returns 404 (not an empty collection) for to-one relationships that
        have not been set yet, e.g. an IAP with no price schedule.
        """
        try:
            return self.get(path, **params)
        except SystemExit as error:
            if " -> 404" in str(error):
                return {}
            raise

    def get_all(self, path: str, **params) -> list[dict]:
        """GET every page of a collection.

        Price-point collections run to several hundred entries, so a single
        limit=200 page silently misses higher price tiers.
        """
        results: list[dict] = []
        page = self.get(path, **params)
        while True:
            results.extend(page.get("data", []))
            next_url = (page.get("links") or {}).get("next")
            if not next_url:
                return results
            page = self._request("GET", next_url)

    def post(self, path: str, payload: dict) -> dict:
        return self._request("POST", path, payload)

    def patch(self, path: str, payload: dict) -> dict:
        return self._request("PATCH", path, payload)

    def apps(self) -> list[dict]:
        return self.get("/apps", limit=200).get("data", [])

    def bundle_ids(self) -> list[dict]:
        results: list[dict] = []
        page = self.get("/bundleIds", limit=200)
        while True:
            results.extend(page.get("data", []))
            next_url = page.get("links", {}).get("next")
            if not next_url:
                return results
            page = self._request("GET", next_url)
