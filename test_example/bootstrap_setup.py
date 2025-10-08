#!/usr/bin/env python3
import os
import sys
from typing import Dict

import hvac

VAULT_ADDR = os.environ.get("VAULT_ADDR", "http://127.0.0.1:8200")
VAULT_TOKEN = os.environ.get("VAULT_TOKEN")  # admin/root token required for setup

MOUNT_POINT = os.environ.get("MOUNT_POINT", "kv")
SECRET_RELATIVE_PATH = os.environ.get("RELATIVE_PATH", "test/test_1")
SECRET_DATA: Dict[str, str] = {
    "username": os.environ.get("SECRET_USERNAME", "username_test"),
    "password": os.environ.get("SECRET_PASSWORD", "password_1234"),
}

POLICY_NAME = os.environ.get("POLICY_NAME", "test-read")
POLICY_HCL = os.environ.get(
    "POLICY_HCL",
    "\n".join(
        [
            "path \"kv/data/test/*\"     { capabilities = [\"read\",\"list\"] }",
            "path \"kv/metadata/test/*\" { capabilities = [\"list\",\"read\"] }",
        ]
    ),
)

ALICE_USER = os.environ.get("ALICE_USER", "alice")
ALICE_PASS = os.environ.get("ALICE_PASS", "alice_password")
BOB_USER = os.environ.get("BOB_USER", "bob")
BOB_PASS = os.environ.get("BOB_PASS", "bob_password")


def get_admin_client() -> hvac.Client:
    if not VAULT_TOKEN:
        raise RuntimeError("Set VAULT_TOKEN (admin) in the environment to run bootstrap.")
    client = hvac.Client(url=VAULT_ADDR, token=VAULT_TOKEN)
    if not client.is_authenticated():
        raise RuntimeError("Admin token not authenticated.")
    return client


def ensure_kv_v2(client: hvac.Client, mount_point: str) -> None:
    mounts = client.sys.list_mounted_secrets_engines()
    mounts = mounts.get("data", mounts)
    entry = mounts.get(f"{mount_point}/")
    if not entry:
        client.sys.enable_secrets_engine(
            backend_type="kv",
            path=mount_point,
            options={"version": "2"},
        )
        print(f"Enabled KV v2 at '{mount_point}/'")
        return
    if entry.get("type") == "kv" and entry.get("options", {}).get("version") != "2":
        # Attempt to upgrade to v2 via tune
        client.sys.tune_mount_configuration(path=mount_point, options={"version": "2"})
        print(f"Tuned '{mount_point}/' to KV v2")
    else:
        print(f"KV already present at '{mount_point}/'")


def ensure_policy(client: hvac.Client, name: str, policy_hcl: str) -> None:
    client.sys.create_or_update_policy(name=name, policy=policy_hcl)
    print(f"Policy ensured: {name}")


def ensure_userpass_enabled(client: hvac.Client) -> None:
    methods = client.sys.list_auth_methods()
    methods = methods.get("data", methods)
    if "userpass/" not in methods:
        client.sys.enable_auth_method(method_type="userpass")
        print("Enabled userpass auth method")
    else:
        print("userpass auth already enabled")


def ensure_user(client: hvac.Client, username: str, password: str, policies: str = "") -> None:
    client.auth.userpass.create_or_update_user(
        username=username,
        password=password,
        policies=policies,
    )
    print(f"User ensured: {username} (policies='{policies}')")


def ensure_secret(client: hvac.Client, mount_point: str, relative_path: str, data: Dict[str, str]) -> None:
    client.secrets.kv.v2.create_or_update_secret(
        mount_point=mount_point,
        path=relative_path,
        secret=data,
    )
    print(f"Secret written at {mount_point}/{relative_path}")


def verify_read(username: str, password: str) -> None:
    user_client = hvac.Client(url=VAULT_ADDR)
    user_client.auth.userpass.login(username=username, password=password)
    ok = user_client.is_authenticated()
    print(f"Login {username}: {'ok' if ok else 'failed'}")
    if not ok:
        return
    try:
        secret = user_client.secrets.kv.v2.read_secret_version(
            mount_point=MOUNT_POINT,
            path=SECRET_RELATIVE_PATH,
        )
        print(f"Read as {username}: {secret['data']['data']}")
    except hvac.exceptions.Forbidden:
        print(f"Read as {username}: permission denied")
    except hvac.exceptions.InvalidPath:
        print(f"Read as {username}: secret not found")


def main() -> int:
    print(f"VAULT_ADDR={VAULT_ADDR}")
    admin = get_admin_client()
    ensure_kv_v2(admin, MOUNT_POINT)
    ensure_secret(admin, MOUNT_POINT, SECRET_RELATIVE_PATH, SECRET_DATA)
    ensure_policy(admin, POLICY_NAME, POLICY_HCL)
    ensure_userpass_enabled(admin)
    ensure_user(admin, ALICE_USER, ALICE_PASS, policies=POLICY_NAME)
    ensure_user(admin, BOB_USER, BOB_PASS, policies="")

    print("\nVerifying access...")
    verify_read(ALICE_USER, ALICE_PASS)
    verify_read(BOB_USER, BOB_PASS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
