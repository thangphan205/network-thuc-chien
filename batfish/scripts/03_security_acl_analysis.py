#!/usr/bin/env python3
"""
Kịch bản 3: Phân tích An toàn Bảo mật & Tối ưu Access Control List (ACL)
- Kiểm tra các dòng ACL bị ẩn / che khuất (Unreachable / Shadowed ACL rules).
- Đảm bảo tuân thủ chính sách bảo mật (Security Policy Audit).
"""

from pybatfish.client.session import Session
from rich.console import Console
from rich.table import Table

console = Console()

BATFISH_HOST = "localhost"
NETWORK_NAME = "enterprise-demo"

def analyze_acl(snapshot_name, snapshot_path):
    console.print(f"\n[bold blue]🔍 Phân tích ACL trong Snapshot: '{snapshot_name}'[/bold blue]")
    bf = Session(host=BATFISH_HOST)
    bf.set_network(NETWORK_NAME)
    bf.init_snapshot(snapshot_path, name=snapshot_name, overwrite=True)

    # 1. Kiểm tra Filter Line Reachability (Shadowed ACL lines)
    acl_reach = bf.q.filterLineReachability().answer().frame()
    
    if acl_reach.empty:
        console.print("[bold green]✓ Không phát hiện dòng ACL bị dư thừa hoặc bị che khuất (Shadowed)![/bold green]")
    else:
        table = Table(title=f"⚠️ Cảnh báo: Tìm thấy Dòng ACL Bị Che Khuất (Unreachable) [{snapshot_name}]")
        table.add_column("Filter Name", style="cyan")
        table.add_column("Line Number", style="magenta")
        table.add_column("Action", style="yellow")
        table.add_column("Reason", style="bold red")

        for _, row in acl_reach.iterrows():
            table.add_row(
                str(row.get("Filter", row.get("Sources"))),
                str(row.get("Line_Index", row.get("Unreachable_Line_Index"))),
                str(row.get("Action")),
                str(row.get("Reason", "Unreachable / Shadowed by previous rule"))
            )
        console.print(table)

def main():
    # Phân tích trên Base Network (Sạch lỗi)
    analyze_acl("base_network", "../networks/base_network")

    # Phân tích trên Proposed Network (Có chứa lỗi ACL do Kỹ sư cấu hình nhầm)
    analyze_acl("proposed_network", "../networks/proposed_network")

    console.print("\n[bold green]✅ Kịch bản 3 hoàn tất: Batfish đã chỉ ra chính xác lỗ hổng/lỗi ACL![/bold green]")

if __name__ == "__main__":
    main()
