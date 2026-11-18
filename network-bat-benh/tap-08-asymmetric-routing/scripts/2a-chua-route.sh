#!/usr/bin/env bash
# Thuoc 2a — Chua tan goc: sua route de duong ve DI QUA CUNG firewall voi duong di.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
buoc "Thuốc 2a (chữa gốc) — sửa route trên server: về LAN client qua fw-a"
server_ve b; luat_stateful $FWA; luat_stateful $FWB; dat_loose $FWA 0; dat_loose $FWB 0
xoa_conntrack $FWA; xoa_conntrack $FWB; zero_dem $FWA; zero_dem $FWB
echo "  TRƯỚC: server về qua $(server_dang_ve) (fw-b) -> curl HTTP $(curl_thu)"
server_ve a; xoa_conntrack $FWA; xoa_conntrack $FWB; zero_dem $FWA; zero_dem $FWB
echo "  SAU:   server về qua $(server_dang_ve) (fw-a) -> curl HTTP $(curl_thu)   gói INVALID DROP ở fw-b: $(so_invalid $FWB)"
echo ""
echo "  Nginx trên server thấy client là ai?"
docker logs --tail 1 $SERVER 2>&1 | cut -c1-60 | sed 's/^/     /'
echo ""
echo "👉 Đọc chữ ký:"
echo "   • Không đổi luật firewall nào. Chỉ đổi một dòng route. fw-b trở lại 0 gói INVALID."
echo "   • Nginx giữ nguyên IP thật của client ($IP_CLIENT)."
echo "   • Đây là chữa GỐC khi bạn làm chủ bảng định tuyến ở cả hai đầu."
