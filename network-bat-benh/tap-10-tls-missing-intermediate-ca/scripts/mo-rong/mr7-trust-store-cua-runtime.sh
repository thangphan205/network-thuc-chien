#!/usr/bin/env bash
# ==============================================================================
# MR7 — "CAI CA VAO TRUST STORE" KHONG PHAI MOT VIEC. NO LA NHIEU VIEC.
#
# Server o kich ban nay HOAN TOAN DUNG: chuoi day du, dung thu tu, con han.
# Root CA da duoc cai vao trust store cua he dieu hanh tren CA HAI may client.
# Va hai may van cho ra ket qua khac nhau.
#
# VI SAO:
#   `update-ca-certificates` cap nhat trust store CUA HE DIEU HANH. Co runtime
#   doc trust store do, co runtime KHONG — moi thang mot chinh sach:
#
#     curl / nginx / Go     -> doc trust store cua HDH          ✅
#     Node.js               -> mang danh sach CA RIENG trong binary
#     Java                  -> co keystore RIENG (`cacerts`)
#     Python + certifi (pip)-> dung bundle rieng cua certifi
#
#   VA — day moi la cho lat mat — dieu do con phu thuoc vao CACH IMAGE DUOC
#   DONG GOI, khong chi vao ngon ngu:
#
#     Alpine (lab10-client)     : goi apk `ca-certificates` noi HET moi runtime
#                                 ve trust store HDH. No con sinh lai file
#                                 /etc/ssl/certs/java/cacerts cho Java.
#                                 -> cai CA mot lan, tat ca cung thay.
#     node:22-slim (Debian)     : Node dung danh sach CA nhung san trong binary.
#                                 update-ca-certificates chay THANH CONG, curl
#                                 thay CA ngay, ma Node van khong thay gi.
#
# ⚠️ Day chinh la hinh dang that cua cau "sao may anh chay ma may em khong".
#    Khong phai vi ai lam sai. Vi hai image duoc dong goi theo hai triet ly.
#
# 🧠 Cau hoi dung khi debug: KHONG phai "da cai CA chua?" ma la
#    "RUNTIME NAY co doc cai trust store vua cai khong?"
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

echo "✅ MR7 — server dung hoan toan (chuoi day du). Van de nam o phia client..."
cai_root
cai_root_node
dat_chuoi good

buoc "MAY 1 — ALPINE ($CLIENT): apk ca-certificates noi het moi runtime"
printf "  %-28s " "curl"
_trong_client "curl -s -o /dev/null -w 'HTTP %{http_code}\n' https://$TEN/ || echo FAIL"
printf "  %-28s " "node"
_trong_client "node -e \"fetch('https://$TEN/').then(r=>console.log('HTTP',r.status)).catch(e=>console.log('FAIL',e.cause&&e.cause.code))\""
printf "  %-28s " "python3 + requests"
_trong_client "python3 -c \"import requests
try: print('HTTP', requests.get('https://$TEN/', timeout=5).status_code)
except Exception as e: print('FAIL', type(e).__name__)\""
printf "  %-28s " "java cacerts co root?"
_trong_client "keytool -list -cacerts -storepass changeit 2>/dev/null | grep -qi lab10 && echo 'CO (apk tu sinh lai cacerts)' || echo 'KHONG'"

buoc "MAY 2 — DEBIAN + image Node chinh thuc ($CLIENT_NODE)"
echo "  (root CA da duoc cai vao trust store HDH cua may nay, giong het may 1)"
printf "  %-28s " "curl"
docker exec $CLIENT_NODE sh -c "curl -s -o /dev/null -w 'HTTP %{http_code}\n' https://$TEN/ || echo FAIL" 2>/dev/null
printf "  %-28s " "node (mac dinh)"
docker exec $CLIENT_NODE node -e "fetch('https://$TEN/').then(r=>console.log('HTTP',r.status)).catch(e=>console.log('FAIL',e.cause&&e.cause.code))" 2>/dev/null
printf "  %-28s " "node --use-system-ca"
docker exec $CLIENT_NODE node --use-system-ca -e "fetch('https://$TEN/').then(r=>console.log('HTTP',r.status)).catch(e=>console.log('FAIL',e.cause&&e.cause.code))" 2>/dev/null
printf "  %-28s " "node NODE_EXTRA_CA_CERTS"
docker exec -e NODE_EXTRA_CA_CERTS=$ROOT_TRONG_CLIENT $CLIENT_NODE node -e "fetch('https://$TEN/').then(r=>console.log('HTTP',r.status)).catch(e=>console.log('FAIL',e.cause&&e.cause.code))" 2>/dev/null

echo ""
echo "👉 Doc chu ky:"
echo "   • Server KHONG doi mot byte nao giua hai bang tren."
echo "   • Tren ca hai may, curl deu 200 — trust store HDH hoan toan on."
echo "   • Tren may Debian, Node van hong. No khong doc trust store do."
echo "   • Chua cho Node: NODE_EXTRA_CA_CERTS=<file CA>, hoac --use-system-ca"
echo "     (Node 22+), hoac dung image co san CA nhu Alpine."
echo ""
echo "   ⚠️ KHONG chua bang NODE_TLS_REJECT_UNAUTHORIZED=0. Do la tat xac thuc"
echo "      TLS cho TOAN BO tien trinh — bien mot loi cau hinh thanh mot lo hong"
echo "      man-in-the-middle vinh vien, va no se song sot qua moi dot review."
echo ""
echo "   🧠 Bang can nho khi debug TLS trong container:"
echo "        curl OK  +  runtime HONG   ->  trust store CUA RUNTIME, khong phai HDH"
echo "        curl HONG + runtime HONG   ->  trust store HDH, hoac loi phia server"
