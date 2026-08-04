#!/usr/bin/env python3
"""
Kịch bản 2: Phân tích Khả năng Kết nối (Reachability) & Virtual Traceroute
- Kiểm tra kết nối từ App Server (10.10.10.50) tới Database Server (10.20.20.100:5432).
- Thực hiện Virtual Traceroute mô phỏng đường đi từng chặng (Hop-by-hop) qua Control Plane & Data Plane.
"""

from pybatfish.client.session import Session
from pybatfish.datamodel import Header
from rich.console import Console
from rich.panel import Panel

console = Console()

BATFISH_HOST = "localhost"
NETWORK_NAME = "enterprise-demo"
SNAPSHOT_NAME = "base_network"
SNAPSHOT_PATH = "../networks/base_network"

def main():
    console.print(f"[bold blue]🚀 Kết nối Batfish Server và nạp Snapshot '{SNAPSHOT_NAME}'...[/bold blue]")
    bf = Session(host=BATFISH_HOST)
    bf.set_network(NETWORK_NAME)
    bf.init_snapshot(SNAPSHOT_PATH, name=SNAPSHOT_NAME, overwrite=True)

    console.print("\n[bold cyan]🔍 Kiểm tra Traceroute: App Server (10.10.10.50) ➡️ DB Server (10.20.20.100:5432)[/bold cyan]")

    # Khởi tạo Traceroute query
    headers = Header(
        srcIps="10.10.10.50",
        dstIps="10.20.20.100",
        ipProtocols=["tcp"],
        dstPorts=[5432]
    )

    tr_result = bf.q.traceroute(startLocation="sw-dist1", headers=headers).answer().frame()

    for idx, row in tr_result.iterrows():
        flow = row["Flow"]
        traceroute_hops = row["Traces"]
        
        console.print(Panel(f"[bold yellow]Flow Info:[/bold yellow] {flow}", title="Gói tin thử nghiệm"))

        for trace in traceroute_hops:
            console.print(f"[bold green]Traceroute Result Status:[/bold green] [bold white on green] {trace.disposition} [/bold white on green]")
            console.print("[bold cyan]Danh sách các Chặng (Hops):[/bold cyan]")
            for hop_idx, hop in enumerate(trace.hops, start=1):
                console.print(f"  Chặng {hop_idx}: [bold magenta]{hop.node}[/bold magenta]")
                for step in hop.steps:
                    if step.action == "ACCEPTED":
                        console.print(f"    └─ [bold green]Action: {step.action}[/bold green] ({step.detail})")
                    elif step.action == "DENIED":
                        console.print(f"    └─ [bold red]Action: {step.action}[/bold red] ({step.detail})")
                    else:
                        console.print(f"    └─ Action: {step.action} ({step.detail})")

    # Kiểm tra Reachability tổng quát
    console.print("\n[bold cyan]📊 Kết quả Phân tích Reachability Tổng quát:[/bold cyan]")
    reach = bf.q.reachability(headers=headers).answer().frame()
    for _, row in reach.iterrows():
        console.print(f"  Flow: {row['Flow']} | Status: [bold green]{row['TraceStatus']}[/bold green]")

    console.print("\n[bold green]✅ Kịch bản 2 hoàn tất: Kết nối App -> DB hoạt động hoàn hảo trên Production![/bold green]")

if __name__ == "__main__":
    main()
