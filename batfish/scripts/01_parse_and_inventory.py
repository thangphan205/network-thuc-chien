#!/usr/bin/env python3
"""
Kịch bản 1: Phân tích Cú pháp Cấu hình & Trích xuất Danh mục Mạng (Inventory)
- Kiểm tra tính hợp lệ syntax của file cấu hình Cisco IOS.
- Trích xuất danh sách Giao diện (Interfaces), IP Addresses, và BGP Neighbors.
"""

import sys
from pybatfish.client.session import Session
from rich.console import Console
from rich.table import Table

console = Console()

BATFISH_HOST = "localhost"
NETWORK_NAME = "enterprise-demo"
SNAPSHOT_NAME = "base_network"
SNAPSHOT_PATH = "../networks/base_network"

def main():
    console.print(f"[bold blue]🚀 Đang kết nối tới Batfish Server tại {BATFISH_HOST}...[/bold blue]")
    bf = Session(host=BATFISH_HOST)

    bf.set_network(NETWORK_NAME)
    console.print(f"[green]✓ Đã tạo/chọn Network:[/green] {NETWORK_NAME}")

    console.print(f"[yellow]📦 Đang tải Snapshot '{SNAPSHOT_NAME}' từ path '{SNAPSHOT_PATH}'...[/yellow]")
    bf.init_snapshot(SNAPSHOT_PATH, name=SNAPSHOT_NAME, overwrite=True)
    console.print(f"[bold green]✓ Snapshot '{SNAPSHOT_NAME}' khởi tạo thành công![/bold green]\n")

    # 1. Kiểm tra trạng thái Parse cấu hình
    console.print("[bold cyan]1. Kiểm tra trạng thái Parse file cấu hình:[/bold cyan]")
    parse_status = bf.q.fileParseStatus().answer().frame()
    
    table_parse = Table(title="File Parse Status")
    table_parse.add_column("File Name", style="magenta")
    table_parse.add_column("Status", style="green")
    table_parse.add_column("Format", style="cyan")

    for _, row in parse_status.iterrows():
        table_parse.add_row(row["File_Name"], row["Status"], str(row["Format"]))
    console.print(table_parse)
    console.print()

    # 2. Trích xuất danh sách IP Owner (Interface IP Addresses)
    console.print("[bold cyan]2. Trích xuất Danh sách IP và Interface:[/bold cyan]")
    ip_owners = bf.q.ipOwners().answer().frame()

    table_ip = Table(title="Interface IP Inventory")
    table_ip.add_column("Node", style="bold yellow")
    table_ip.add_column("Interface", style="cyan")
    table_ip.add_column("IP Address", style="bold green")
    table_ip.add_column("Mask Length", style="white")

    for _, row in ip_owners.iterrows():
        table_ip.add_row(row["Node"], row["Interface"], row["IP"], str(row["Mask"]))
    console.print(table_ip)
    console.print()

    # 3. Trích xuất cấu hình BGP Neighbors
    console.print("[bold cyan]3. Trích xuất Cấu hình BGP Peers:[/bold cyan]")
    bgp_peers = bf.q.bgpPeerConfiguration().answer().frame()

    table_bgp = Table(title="BGP Peer Configuration")
    table_bgp.add_column("Node", style="bold yellow")
    table_bgp.add_column("Local AS", style="magenta")
    table_bgp.add_column("Remote AS", style="cyan")
    table_bgp.add_column("Destination IP", style="green")

    for _, row in bgp_peers.iterrows():
        table_bgp.add_row(
            row["Node"],
            str(row["Local_AS"]),
            str(row["Remote_AS"]),
            str(row["Destination_IP"])
        )
    console.print(table_bgp)
    console.print("\n[bold green]✅ Kịch bản 1 hoàn tất thành công![/bold green]")

if __name__ == "__main__":
    main()
