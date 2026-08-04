#!/usr/bin/env python3
"""Stage 'unit test cau hinh' trong pipeline Validation-first - chay TRUOC
khi apply len digital-twin/canary.

Yeu cau Batfish service dang chay (xem README.md muc "Batfish pre-check"):
    docker run -d --name batfish -p 9997:9997 -p 9996:9996 batfish/allinone

Script doc cac file config trong thu muc `configs/` (export tu `show
running-config` cua tung thiet bi) va hoi Batfish co ton tai loi tham chieu
(undefined ACL/route-map...) hay khong TRUOC khi cham vao digital-twin.
"""
import sys

from pybatfish.client.session import Session
from pybatfish.question import load_questions

NETWORK_NAME = "cicd-validation-lab"
SNAPSHOT_NAME = "candidate"
CONFIGS_DIR = "configs"


def main() -> None:
    bf = Session(host="localhost")
    bf.set_network(NETWORK_NAME)
    bf.init_snapshot(CONFIGS_DIR, name=SNAPSHOT_NAME, overwrite=True)
    load_questions()

    issues = bf.q.undefinedReferences().answer().frame()
    if not issues.empty:
        print(issues.to_string())
        print("Batfish: phat hien loi undefined reference - DUNG pipeline.")
        sys.exit(1)

    print("Batfish: khong phat hien loi. Cho phep di tiep sang digital-twin.")


if __name__ == "__main__":
    main()
