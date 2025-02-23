# VXLAN 1: VLAN - Cấu hình kết nối Server 1 và Server 2

## Cấu hình switch cumulus1

```bash
nv set system hostname cumulus1
nv set interface swp1 bridge domain br_default
nv set interface swp2 bridge domain br_default access 100
nv set bridge domain br_default vlan 100
nv config apply
```

## Cấu hình switch cumulus2

```bash
nv set system hostname cumulus2
nv set interface swp1 bridge domain br_default
nv set interface swp2 bridge domain br_default access 100
nv set bridge domain br_default vlan 100
nv config apply
```

## Cumulus commands

show mac address table: ```nv show bridge domain br_default mac-table```
clear mac address table: ```nv action clear bridge domain br_default mac-table dynamic```

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
