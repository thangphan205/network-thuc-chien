#!/usr/bin/env bash
# MR4 — Route doi GIUA PHIEN: bat tay xong xuoi, chet giua chung.
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh
buoc "MR4 — server ve qua fw-a luc bat tay, DOI sang fw-b sau 2 giay (route flap / failover)"
server_ve a; luat_stateful $FWA; luat_stateful $FWB; dat_loose $FWA 0; dat_loose $FWB 0
xoa_conntrack $FWA; xoa_conntrack $FWB; zero_dem $FWA; zero_dem $FWB
( sleep 2; server_ve b ) &
echo "  1 ket noi TCP: GET #1 (qua fw-a, OK) -> route doi sang fw-b -> GET #2 tren CHINH ket noi do:"
N=$(hai_get_giua_chung 5)
wait
echo "  👉 So phan hoi HTTP 200: ${N}/2"
echo "  fw-b goi INVALID DROP = $(so_invalid $FWB)   (client retransmit lien tuc, moi lan lai roi vao fw-b)"
echo ""
echo "👉 Doc chu ky — SO VOI KB2:"
echo "   • KB2: chet NGAY tu bat tay (curl khong bao gio nhan 200)."
echo "   • MR4: bat tay + GET #1 chay tot, chet GIUA PHIEN. Chan doan 'mang on dinh luc dau' la sai."
echo "   • Nguyen nhan ngoai doi: BGP/OSPF hoi tu lai, ECMP doi hash, failover cap firewall,"
echo "     link flap. Chi mot phan phien dang mo bi chet, phan con lai van song."
