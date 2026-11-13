"""List or revoke Apple development certificates through the App Store Connect API.

  asc_certs.py list                 → prints the ids of all development certificates
  asc_certs.py revoke-new <file>    → revokes development certificates not listed in <file>
  asc_certs.py revoke-ci            → revokes development certificates made by CI ("Created via API")

Reads ASC_KEY_ID, ASC_ISSUER_ID and the key at $RUNNER_TEMP/AuthKey.p8.
Only development certificates are touched; distribution certificates are never revoked.
"""
import json
import os
import sys
import time
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
TYPES = {"DEVELOPMENT", "IOS_DEVELOPMENT"}


def token():
    key = open(os.path.join(os.environ["RUNNER_TEMP"], "AuthKey.p8")).read()
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def request(method, url):
    req = urllib.request.Request(url, method=method, headers={"Authorization": "Bearer " + token()})
    with urllib.request.urlopen(req) as r:
        body = r.read()
        return json.loads(body) if body else None


def dev_certs():
    out, url = [], API + "/certificates?limit=200"
    while url:
        page = request("GET", url)
        out += [c for c in page["data"] if c["attributes"].get("certificateType") in TYPES]
        url = page.get("links", {}).get("next")
    return out


def main():
    if sys.argv[1] == "list":
        for c in dev_certs():
            print(c["id"])
    elif sys.argv[1] == "revoke-new":
        before = set(open(sys.argv[2]).read().split())
        for c in dev_certs():
            if c["id"] not in before:
                print("Revoking", c["id"], c["attributes"].get("name"))
                request("DELETE", f"{API}/certificates/{c['id']}")

    elif sys.argv[1] == "revoke-ci":
        for c in dev_certs():
            if "Created via API" in (c["attributes"].get("name") or ""):
                print("Revoking", c["id"], c["attributes"].get("name"))
                request("DELETE", f"{API}/certificates/{c['id']}")


main()
