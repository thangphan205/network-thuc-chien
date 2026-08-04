#!/usr/bin/env python3
"""
Kịch bản 4: Phân tích Tác động Thay đổi (Differential Analysis) - CI/CD Guardrail
- So sánh Snapshot 'base_network' (Production) vs 'proposed_network' (Pull Request).
- Phát hiện tự động sự cố sập kết nối (Reachability Loss) và lỗi BGP Peering trước khi merge code.
"""

import sys
from pybatfish.client.session import Session
from pybatfish.datamodel import Header
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

console = Console()

BATFISH_HOST = "localhost"
NETWORK_NAME = "enterprise-demo"
BASE_PATH = "../networks/base_network"
PROPOSED_PATH = "../networks/proposed_network"

def main():
    console.print("[bold blue]🚀 Đang kết nối Batfish Server và khởi tạo 2 Snapshot để So sánh...[/bold blue]")
    bf = Session(host=BATFISH_HOST)
    bf.set_network(NETWORK_NAME)

    # Nạp Base Snapshot
    bf.init_snapshot(BASE_PATH, name="base_network", overwrite=True)
    # Nạp Proposed Snapshot
    bf.init_snapshot(PROPOSED_PATH, name="proposed_network", overwrite=True)

    console.print("\n[bold cyan]=======================================================[/bold cyan]")
    console.print("[bold yellow]1. KIỂM TRA BGP SESSION STATUS (PROPOSED NETWORK)[/bold yellow]")
    console.print("[bold cyan]=======================================================[/bold cyan]")
    
    bf.set_snapshot("proposed_network")
    bgp_status = bf.q.bgpSessionStatus().answer().frame()
    
    table_bgp = Table(title="Trạng thái BGP Session trong Proposed Network")
    table_bgp.add_column("Node", style="yellow")
    table_bgp.add_column("Remote Node", style="cyan")
    table_bgp.add_column("Session Type", style="magenta")
    table_bgp.add_column("Status", style="bold red")

    has_bgp_error = False
    for _, row in bgp_status.iterrows():
        status = str(row["VRF_Status"]) if "VRF_Status" in row else str(row.get("Established_Status", "UNKNOWN"))
        if "NOT" in status or "DISCONNECTED" in status or "FAILED" in status:
            has_bgp_error = True
            table_bgp.add_row(row["Node"], str(row.get("Remote_Node", "N/A")), str(row["Session_Type"]), f"[bold red]{status}[/bold red]")
        else:
            table_bgp.add_row(row["Node"], str(row.get("Remote_Node", "N/A")), str(row["Session_Type"]), f"[bold green]{status}[/bold green]")
    
    console.print(table_bgp)

    console.print("\n[bold cyan]=======================================================[/bold cyan]")
    console.print("[bold yellow]2. DIFFERENTIAL REACHABILITY ANALYSIS (SO SÁNH BASE VS PROPOSED)[/bold yellow]")
    console.print("[bold cyan]=======================================================[/bold cyan]")

    # Thực hiện Differential Reachability Test
    headers = Header(
        srcIps="10.10.10.50",
        dstIps="10.20.20.100",
        ipProtocols=["tcp"],
        dstPorts=[5432]
    )

    diff_reach = bf.q.differentialReachability(
        headers=headers
    ).answer(snapshot="proposed_network", reference_snapshot="base_network").frame()

    has_reachability_loss = False

    if diff_reach.empty:
        console.print("[bold green]✓ Không phát hiện sự cố gián đoạn kết nối![/bold green]")
    else:
        has_reachability_loss = True
        console.print(Panel("[bold red]🚨 PHÁT HIỆN SỰ CỐ NGHIÊM TRỌNG: KẾT NỐI BỊ MẤT SAU THAY ĐỔI![/bold red]", border_style="red"))
        
        table_diff = Table(title="Kết quả Differential Reachability")
        table_diff.add_column("Flow", style="yellow")
        table_diff.add_column("Base Status (Trước)", style="bold green")
        table_diff.add_column("Proposed Status (Sau)", style="bold red")

        for _, row in diff_reach.iterrows():
            table_diff.add_row(
                str(row["Flow"]),
                str(row.get("Base_TraceStatus", "ACCEPTED")),
                str(row.get("Proposed_TraceStatus", "DENIED"))
            )
        console.print(table_diff)

    # Đưa ra phán quyết cho CI/CD Pipeline
    console.print("\n[bold cyan]=======================================================[/bold cyan]")
    console.print("[bold yellow]KẾT QUẢ KIỂM THỬ TỰ ĐỘNG (CI/CD PIPELINE AUDIT)[/bold yellow]")
    console.print("[bold cyan]=======================================================[/bold cyan]")

    if has_reachability_loss or has_bgp_error:
        console.print("[bold white on red] ❌ PIPELINE FAILED: PULL REQUEST BỊ TỪ CHỐI DO GÂY LỖI MẠNG! [/bold white on red]")
        console.print("[red]Lý do: Thay đổi cấu hình làm sập kết nối App -> DB Server hoặc hỏng BGP Session.[/red]")
        sys.exit(1)
    else:
        console.print("[bold white on green] ✅ PIPELINE PASSED: THAY ĐỔI AN TOÀN, ĐỦ ĐIỀU KIỆN MERGE CODE! [/bold white on green]")
        sys.exit(0)

if __name__ == "__main__":
    main()
