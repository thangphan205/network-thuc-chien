#!/usr/bin/env python3
"""Mo hinh GitOps Pull: poller nay chay tren jump-host, TU kéo Git về và áp
dụng config idempotent lên thiết bị - không ai từ bên ngoài SSH thẳng vào
thiết bị để đẩy config (khác Mô hình 1 - Push).

Xem ly thuyet: ../../README.md muc "Mo hinh 2: GitOps Pull"
"""
import argparse
import os
import sys
import time

import yaml
from napalm import get_network_driver

DESIRED_STATE_FILE = os.path.join(os.path.dirname(__file__), "desired_state.yml")


def git_pull_if_configured() -> None:
    """Trong trien khai that, desired_state.yml nam o mot git repo rieng
    (config repo) duoc pull ve truoc moi vong lap. Bat buoc qua bien moi
    truong GIT_CONFIG_REPO_PATH de khong yeu cau GitPython khi chay demo
    local don gian (desired_state.yml da nam san trong repo lab nay)."""
    repo_path = os.environ.get("GIT_CONFIG_REPO_PATH")
    if not repo_path:
        return
    from git import Repo

    Repo(repo_path).remotes.origin.pull()


def render_candidate_config(dns_servers: list[str]) -> str:
    return "\n".join(f"ip name-server {ip}" for ip in dns_servers)


def apply_desired_state(name: str, cfg: dict, username: str, password: str, secret: str) -> None:
    driver = get_network_driver("ios")
    device = driver(
        hostname=cfg["host"],
        username=username,
        password=password,
        optional_args={"secret": secret},
    )
    device.open()
    try:
        candidate = render_candidate_config(cfg["dns_servers"])
        device.load_merge_candidate(config=candidate)
        diff = device.compare_config()
        if not diff:
            print(f"[{name}] khong lech - bo qua (idempotent)")
            device.discard_config()
            return
        print(f"[{name}] phat hien lech, se apply:\n{diff}")
        device.commit_config()
        print(f"[{name}] da apply thanh cong")
    finally:
        device.close()


def run_once() -> None:
    git_pull_if_configured()
    with open(DESIRED_STATE_FILE) as f:
        desired = yaml.safe_load(f)["devices"]

    username = os.environ["LAB_DEVICE_USERNAME"]
    password = os.environ["LAB_DEVICE_PASSWORD"]
    secret = os.environ.get("LAB_ENABLE_PASSWORD", "")

    for name, cfg in desired.items():
        apply_desired_state(name, cfg, username, password, secret)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true", help="Chay 1 vong roi thoat (dung cho CI/demo)")
    parser.add_argument("--interval", type=int, default=300, help="Giay giua moi vong poll (mac dinh 300s)")
    args = parser.parse_args()

    if args.once:
        run_once()
        return

    while True:
        try:
            run_once()
        except Exception as exc:  # noqa: BLE001 - poller không được chết vì 1 lỗi tạm thời
            print(f"loi trong vong poll: {exc}", file=sys.stderr)
        time.sleep(args.interval)


if __name__ == "__main__":
    main()
