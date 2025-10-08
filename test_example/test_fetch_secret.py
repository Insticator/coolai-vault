#!/usr/bin/env python3
import os
import sys
from typing import Tuple

import hvac

VAULT_ADDR = os.environ.get("VAULT_ADDR", "http://127.0.0.1:8200")
MOUNT_POINT = os.environ.get("MOUNT_POINT", "kv")            # KV v2 mount
RELATIVE_PATH = os.environ.get("RELATIVE_PATH", "test/test_1")  # path under the mount

# Example credentials (override via env if needed)
ALICE_USER = os.environ.get("ALICE_USER", "alice")
ALICE_PASS = os.environ.get("ALICE_PASS", "alice_password")
BOB_USER = os.environ.get("BOB_USER", "bob")
BOB_PASS = os.environ.get("BOB_PASS", "bob_password")


def login_userpass(username: str, password: str) -> hvac.Client:
    client = hvac.Client(url=VAULT_ADDR)
    client.auth.userpass.login(username=username, password=password)
    if not client.is_authenticated():
        raise RuntimeError(f"Auth failed for {username}")
    return client


def read_kv_v2(client: hvac.Client, mount_point: str, relative_path: str) -> Tuple[bool, dict]:
    try:
        secret = client.secrets.kv.v2.read_secret_version(
            mount_point=mount_point,
            path=relative_path,
        )
        return True, secret["data"]["data"]
    except hvac.exceptions.Forbidden:
        return False, {"error": "permission denied"}
    except hvac.exceptions.InvalidPath:
        return False, {"error": "secret not found"}
    except Exception as exc:
        return False, {"error": str(exc)}


def try_user(username: str, password: str) -> None:
    print(f"\n== As {username} ==")
    try:
        client = login_userpass(username, password)
    except Exception as exc:
        print(f"login error: {exc}")
        return
    ok, result = read_kv_v2(client, MOUNT_POINT, RELATIVE_PATH)
    full_path = f"{MOUNT_POINT}/{RELATIVE_PATH}"
    if ok:
        print(f"secret {full_path}: {result}")
    else:
        print(f"cannot read {full_path}: {result.get('error')}")


def main() -> int:
    print(f"VAULT_ADDR={VAULT_ADDR}")
    print(f"MOUNT_POINT={MOUNT_POINT} RELATIVE_PATH={RELATIVE_PATH}")
    try_user(ALICE_USER, ALICE_PASS)
    try_user(BOB_USER, BOB_PASS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
