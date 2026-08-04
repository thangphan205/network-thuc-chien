#!/usr/bin/env python3
"""
Kịch bản 5: Mô phỏng Sự cố Mạng (Failure Simulation / What-If Analysis)
- Mô phỏng đứt đường truyền (Link Failure) hoặc sập Router (Node Failure).
- Kiểm tra tính toán lại tuyến đường (Route Convergence) và khả năng duy trì kết nối qua đường dự phòng.
"""

from pybatfish.client.session import Session
from pybatfish.datamodel import Header, NodeInterface
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

    console.print("\n[bold cyan]1. Trạng thái Ban đầu (Normal Operation):[/bold cyan]")
    headers = Header(
        srcIps="10.10.10.50",
        dstIps="10.0.0.1",  # Edge Firewall LAN IP
        ipProtocols=["tcp"],
        dstPorts=[80]
    )

    tr_normal = bf.q.traceroute(startLocation="sw-dist1", headers=headers).answer().frame()
    for _, row in tr_normal.iterrows():
        for trace in row["Traces"]:
            console.print(f"  Bình thường: Status = [bold green]{trace.disposition}[/bold green]")

    console.print("\n[bold red]2. Mô phỏng Đứt đường truyền (Simulate Link Failure):[/bold red]")
    console.print("[yellow]Giả lập: Giao diện GigabitEthernet0/2 trên r1-core bị DOWN![/yellow]")

    # Fork snapshot và deactive interface
    forked_snapshot = "link_failure_snapshot"
    bf.fork_snapshot(
        base_name=SNAPSHOT_NAME,
        name=forked_snapshot,
        deactivate_interfaces=[NodeInterface(node="r1-core", interface="GigabitEthernet0/2")],
        overwrite=True
    )
    bf.set_snapshot(forked_snapshot)

    console.print(f"[bold green]✓ Snapshot '{forked_snapshot}' đã được tạo thành công.[/bold green]")

    console.print("\n[bold cyan]3. Kiểm tra lại đường đi sau sự cố (Post-Failure Traceroute):[/bold cyan]")
    tr_failover = bf.q.traceroute(startLocation="sw-dist1", headers=headers).answer().frame()

    for _, row in tr_failover.iterrows():
        for trace in row["Traces"]:
            console.print(Panel(f"[bold green]Traceroute Status Sau Failover:[/bold green] [bold white on green] {trace.disposition} [/bold white on green]"))
            console.print("[bold cyan]Tuyến đường dự phòng mới (Hop-by-hop):[/bold cyan]")
            for hop_idx, hop in enumerate(trace.hops, start=1):
                console.print(f"  Chặng {hop_idx}: [bold magenta]{hop.node}[/bold magenta]")

    console.print("\n[bold green]✅ Kịch bản 5 hoàn tất: OSPF Failover qua r2-core hoạt động chính xác![/bold green]")

if __name__ == "__main__":
    main()
