# VXLAN 2: Static VXLAN Single VNI - Cấu hình kết nối Server 1 và Server 2

## Cấu hình switch cumulus1

```bash
nv unset interface swp1
nv set interface swp1 ip address 10.0.0.1/30
nv set interface swp2 bridge domain br_default access 100
nv set bridge domain br_default vlan 100
nv set bridge domain br_default vlan 100 vni 5100
nv set nve vxlan mac-learning on
nv set nve vxlan source address 10.0.0.1
nv set bridge domain br_default vlan 100 vni 5100 flooding head-end-replication 10.0.0.2
nv config apply
```

## Cấu hình switch cumulus2

```bash
nv unset interface swp1
nv set interface swp1 ip address 10.0.0.2/30
nv set interface swp2 bridge domain br_default access 100
nv set bridge domain br_default vlan 100
nv set bridge domain br_default vlan 100 vni 5100
nv set nve vxlan mac-learning on
nv set nve vxlan source address 10.0.0.2
nv set bridge domain br_default vlan 100 vni 5100 flooding head-end-replication 10.0.0.1
nv config apply
```

## Cấu hình Server 1 (giả lập Router Cisco)

```bash
int g0/0
ip add 192.168.100.101 255.255.255.0
no sh
```

## Cấu hình Server 2 (giả lập Router Cisco)

```bash
int g0/0
ip add 192.168.100.102 255.255.255.0
no sh
```
