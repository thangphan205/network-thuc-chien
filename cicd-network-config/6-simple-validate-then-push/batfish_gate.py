#!/usr/bin/env python3
"""Batfish validate-then-push gate - buoc "unit test cau hinh" DUY NHAT
truoc khi CI tu dong day config that ra thiet bi. Khong co con nguoi
approve, khong canary/rollback (xem README.md).

Chay ba kiem tra tren snapshot 'proposed' (netadmin sua trong PR):
1. ACL/security: filterLineReachability() - phat hien dong ACL bi shadow.
2. Differential reachability: so voi snapshot 'base' - phat hien luong
   traffic App -> DB bi mat sau thay doi.
3. BGP session status: phat hien session BGP bi disconnect.

Ghi ket qua ra gate_report.md de CI post len PR comment. Exit 1 neu co loi -
chan pipeline, KHONG duoc day config ra thiet bi. Exit 0 neu PASS.
"""
import sys

from pybatfish.client.session import Session
from pybatfish.datamodel import HeaderConstraints

NETWORK_NAME = "simple-validate-push-lab"
BASE_PATH = "configs/base"
PROPOSED_PATH = "configs/proposed"
REPORT_PATH = "gate_report.md"

APP_SRC_IP = "10.10.10.50"
DB_DST_IP = "10.20.20.100"
DB_DST_PORT = 5432


def check_acl(bf) -> tuple[bool, str]:
    bf.set_snapshot("proposed")
    acl_reach = bf.q.filterLineReachability().answer().frame()
    if acl_reach.empty:
        return False, "Khong phat hien dong ACL bi du thua hoac bi che khuat (shadowed)."
    lines = ["| Filter | Line | Action | Reason |", "| --- | --- | --- | --- |"]
    for _, row in acl_reach.iterrows():
        lines.append(
            "| {} | {} | {} | {} |".format(
                row.get("Filter", row.get("Sources")),
                row.get("Line_Index", row.get("Unreachable_Line_Index")),
                row.get("Action"),
                row.get("Reason", "Unreachable / Shadowed by previous rule"),
            )
        )
    return True, "\n".join(lines)


def check_reachability(bf) -> tuple[bool, str]:
    headers = HeaderConstraints(
        srcIps=APP_SRC_IP,
        dstIps=DB_DST_IP,
        ipProtocols=["tcp"],
        dstPorts=[DB_DST_PORT],
    )
    diff_reach = (
        bf.q.differentialReachability(headers=headers)
        .answer(snapshot="proposed", reference_snapshot="base")
        .frame()
    )
    if diff_reach.empty:
        return False, "Khong phat hien mat ket noi App -> DB so voi production hien tai."
    lines = ["| Flow | Base (truoc) | Proposed (sau) |", "| --- | --- | --- |"]
    for _, row in diff_reach.iterrows():
        lines.append(
            "| {} | {} | {} |".format(
                row["Flow"],
                row.get("Base_TraceStatus", "ACCEPTED"),
                row.get("Proposed_TraceStatus", "DENIED"),
            )
        )
    return True, "\n".join(lines)


def check_bgp(bf) -> tuple[bool, str]:
    bf.set_snapshot("proposed")
    bgp_status = bf.q.bgpSessionStatus().answer().frame()
    bad_rows = []
    for _, row in bgp_status.iterrows():
        status = str(row.get("Established_Status", row.get("VRF_Status", "UNKNOWN")))
        if "NOT" in status or "DISCONNECTED" in status or "FAILED" in status:
            bad_rows.append((row.get("Node"), row.get("Remote_Node", "N/A"), status))
    if not bad_rows:
        return False, "Khong phat hien BGP session nao bi disconnect trong snapshot proposed."
    lines = ["| Node | Remote Node | Status |", "| --- | --- | --- |"]
    for node, remote, status in bad_rows:
        lines.append("| {} | {} | {} |".format(node, remote, status))
    return True, "\n".join(lines)


def main() -> None:
    bf = Session(host="localhost")
    bf.set_network(NETWORK_NAME)
    bf.init_snapshot(BASE_PATH, name="base", overwrite=True)
    bf.init_snapshot(PROPOSED_PATH, name="proposed", overwrite=True)

    has_acl_issue, acl_report = check_acl(bf)
    has_reachability_loss, reach_report = check_reachability(bf)
    has_bgp_issue, bgp_report = check_bgp(bf)

    failed = has_acl_issue or has_reachability_loss or has_bgp_issue

    report = ["# Batfish Validate-then-Push Gate Report", ""]
    report += ["## 1. ACL / Security Analysis", "", acl_report, ""]
    report += ["## 2. Differential Reachability (App -> DB)", "", reach_report, ""]
    report += ["## 3. BGP Session Status (proposed)", "", bgp_report, ""]
    if failed:
        report += [
            "## Ket luan: :x: FAIL",
            "",
            "Phat hien loi ky thuat (ACL/reachability/BGP). Pipeline dung "
            "lai ngay tai day - **KHONG duoc day config nay ra thiet bi**.",
        ]
    else:
        report += [
            "## Ket luan: :white_check_mark: PASS",
            "",
            "Batfish khong phat hien loi. Neu day la lan chay tren nhanh "
            "main, CI se tu dong day config trong job tiep theo - khong "
            "co buoc cho con nguoi duyet.",
        ]

    with open(REPORT_PATH, "w") as f:
        f.write("\n".join(report) + "\n")
    print("\n".join(report))

    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
