#!/usr/bin/env python3
"""Batfish Change Request gate - stage 'unit test cau hinh' truoc khi cho
phep con nguoi approve va netadmin thuc thi CR tren thiet bi that.

Chay hai kiem tra tren snapshot 'proposed' (config netadmin de xuat trong CR):
1. ACL/security: filterLineReachability() - phat hien dong ACL bi shadow/
   unreachable do sap xep sai thu tu.
2. Differential reachability: so voi snapshot 'base' (config production hien
   tai) - phat hien luong traffic quan trong bi mat sau thay doi.

Ghi ket qua ra cr_report.md (markdown, khong dung mau rich) de CI post len
PR comment cho nguoi duyet doc. Exit 1 neu co loi - chan pipeline truoc khi
toi buoc cho nguoi approve.
"""
import sys

from pybatfish.client.session import Session
from pybatfish.datamodel import Header

NETWORK_NAME = "cr-gate-lab"
BASE_PATH = "configs/base"
PROPOSED_PATH = "configs/proposed"
REPORT_PATH = "cr_report.md"

# Luong traffic quan trong can bao ve: App Server -> Database Server
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
    headers = Header(
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
        return False, "Khong phat hien mat ket noi so voi production hien tai."

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


def main() -> None:
    bf = Session(host="localhost")
    bf.set_network(NETWORK_NAME)
    bf.init_snapshot(BASE_PATH, name="base", overwrite=True)
    bf.init_snapshot(PROPOSED_PATH, name="proposed", overwrite=True)

    has_acl_issue, acl_report = check_acl(bf)
    has_reachability_loss, reach_report = check_reachability(bf)

    failed = has_acl_issue or has_reachability_loss

    report = ["# Batfish Change Request Gate Report", ""]
    report.append("## 1. ACL / Security Analysis")
    report.append("")
    report.append(acl_report)
    report.append("")
    report.append("## 2. Differential Reachability (App -> DB)")
    report.append("")
    report.append(reach_report)
    report.append("")
    if failed:
        report.append("## Ket luan: :x: FAIL")
        report.append("")
        report.append(
            "CR nay lam thay doi hanh vi mang theo huong tieu cuc "
            "(loi ACL va/hoac mat reachability). **Khong duoc chuyen sang buoc duyet.**"
        )
    else:
        report.append("## Ket luan: :white_check_mark: PASS")
        report.append("")
        report.append(
            "Batfish khong phat hien loi. CR du dieu kien chuyen sang "
            "buoc cho nguoi co tham quyen approve truoc khi netadmin thuc thi."
        )

    with open(REPORT_PATH, "w") as f:
        f.write("\n".join(report) + "\n")

    print("\n".join(report))

    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
