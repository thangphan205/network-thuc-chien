#!/usr/bin/env bash
# ==============================================================================
# KB4 — NXDOMAIN.  Chu ky: server TRA LOI, va cau tra loi la "ten do khong ton tai".
#
# Tinh huong ngoai doi: go sai ten mien, quen tao ban ghi A cho dich vu moi, hoac
# ai do xoa nham mot dong trong zone.
#
# Diem quan trong: day KHONG phai su co mang. Moi thu o L2/L3/L4 deu hoan hao.
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

TEN_SAI=wed.lab.local     # go nham 'web' thanh 'wed'
echo "🚨 KB4 — hoi mot ten KHONG co trong zone: $TEN_SAI"
xoa_log_dns

buoc "CHU KY: NXDOMAIN"
in_chu_ky "$TEN_SAI"
echo ""
echo "  --- Goc nhin phia DNS server ---"
log_dns 4 | sed 's/^/  /'
echo ""
echo "👉 Doc chu ky:"
echo "   • dig status = NXDOMAIN va mat ~1 ms. NHANH = server SONG, DA tra loi."
echo "     Doi lap hoan toan voi KB2 (2000 ms, khong ai tra loi)."
echo "   • query toi server > 0, log server ghi ro 'is NXDOMAIN'."
echo "     Ban co bang chung hai chieu: client hoi, server dap."
echo "   • curl bao exit 6 — GIONG HET KB3, nhung dig noi hai chuyen khac han."
echo ""
echo "ℹ️  Ghi chu ky thuat: dnsmasq tra NXDOMAIN voi AUTHORITY: 0 (khong kem SOA),"
echo "    dung nhu mot resolver dem/chuyen tiep. Mot may chu CO THAM QUYEN that"
echo "    (BIND, PowerDNS) se kem them ban ghi SOA trong phan AUTHORITY."
echo ""
echo "👉 Chan doan: ./scripts/test.sh $TEN_SAI"
echo "   (PHAI truyen ten — test.sh mac dinh hoi $TEN, ten do van khoe)"
