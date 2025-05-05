# OSPF numbered Lab

cumulus1-----cumulus2-----cumulus3

[<https://docs.nvidia.com/networking-ethernet-software/cumulus-linux-513/Layer-3/OSPF/Open-Shortest-Path-First-v2-OSPFv2/#ospfv2-numbered>](https://docs.nvidia.com/networking-ethernet-software/cumulus-linux-513/Layer-3/OSPF/Open-Shortest-Path-First-v2-OSPFv2/#ospfv2-numbered)

## Enable OSPF

<https://docs.nvidia.com/networking-ethernet-software/cumulus-linux-513/Layer-3/FRRouting/>

Thực hiện Enable OSPF process trên cả 3 thiết bị cumulus linux:

root@cumulus2:mgmt:~# vi /etc/frr/daemons
ospfd=yes
root@cumulus2:mgmt:~# systemctl restart frr
