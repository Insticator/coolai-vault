#!/usr/bin/env python3
import os
import sys
import json
from typing import Dict, Any

import hvac
from dotenv import load_dotenv


def retrieve_secrets(username: str, password: str, full_path: str | None = None, vault_addr: str | None = None) -> Dict[str, Any]:
    """Login via userpass and either:
    - return one secret at full_path (e.g., "kv/test/test_1"), or
    - list and return all readable KV v2 secrets across all KV v2 mounts.

    Returns a Python dict suitable for JSON serialization.
    """
    load_dotenv(dotenv_path=os.environ.get("DOTENV_PATH", ".env"))
    addr = vault_addr or os.environ.get("VAULT_ADDR", "http://207.58.174.60:8200")

    client = hvac.Client(url=addr)
    client.auth.userpass.login(username=username, password=password)
    if not client.is_authenticated():
        raise RuntimeError("authentication failed")

    # Helper to split a full path "mount/relative/path" -> (mount, relative)
    def split_full_path(p: str) -> tuple[str, str]:
        if "/" not in p:
            raise ValueError("full_path must include mount, e.g., 'kv/test/test_1'")
        mount, rel = p.split("/", 1)
        if not mount or not rel:
            raise ValueError("invalid full_path; expected 'mount/relative' format")
        return mount, rel

    if full_path:
        mount, rel = split_full_path(full_path)
        out: Dict[str, Any] = {"vault_addr": addr, "path": f"{mount}/{rel}"}
        try:
            sec = client.secrets.kv.v2.read_secret_version(mount_point=mount, path=rel)
            out.update({"status": "ok", "data": sec["data"]["data"]})
        except hvac.exceptions.Forbidden:
            out.update({"status": "denied"})
        except hvac.exceptions.InvalidPath:
            out.update({"status": "not_found"})
        return out

    # Otherwise, enumerate across all KV v2 mounts
    mounts = client.sys.list_mounted_secrets_engines()
    mounts = mounts.get("data", mounts)
    kv_v2_mounts = [m.rstrip("/") for m, meta in mounts.items() if meta.get("type") == "kv" and meta.get("options", {}).get("version") == "2"]

    secrets: Dict[str, Dict[str, Any]] = {}

    for mount in kv_v2_mounts:
        def walk(prefix: str) -> None:
            try:
                resp = client.secrets.kv.v2.list_secrets(mount_point=mount, path=prefix)
                keys = resp["data"]["keys"]
            except Exception:
                return
            for key in keys:
                next_rel = f"{prefix}{key}" if prefix else key
                if key.endswith("/"):
                    walk(next_rel)
                else:
                    try:
                        sec = client.secrets.kv.v2.read_secret_version(mount_point=mount, path=next_rel)
                        secrets[f"{mount}/{next_rel}"] = sec["data"]["data"]
                    except Exception:
                        # ignore unreadable or race conditions
                        pass

        walk("")

    return {"vault_addr": addr, "secrets": dict(sorted(secrets.items()))}


if __name__ == "__main__":
    load_dotenv(dotenv_path=os.environ.get("DOTENV_PATH", ".env"))
    username = os.environ.get("USERNAME")
    password = os.environ.get("PASSWORD")
    full_path_arg = sys.argv[1] if len(sys.argv) > 1 else None
    if not (username and password):
        print("Missing USERNAME or PASSWORD. Set them in .env or env vars.")
        sys.exit(1)
    result = retrieve_secrets(username=username, password=password, full_path=full_path_arg)
    print(json.dumps(result, indent=2))


