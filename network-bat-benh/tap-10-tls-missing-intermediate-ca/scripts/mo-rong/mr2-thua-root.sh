#!/usr/bin/env bash
# ==============================================================================
# MR2 — CHUOI THUA ROOT.  Chu ky: 3 cert, num=0, HTTP 200 — VAN CHAY.
#
# Kich ban DUY NHAT trong tap khong lam hong gi ca. No co mat vi mot ly do:
# de ban khong hoc thuoc luat sai "cu khac chuan la chet".
#
# Server gui kem ca root CA. Khong sai ve mat giao thuc — client chi don gian bo
# qua cert cuoi, vi no da co ban root cua chinh minh trong trust store roi.
#
# Nhung no LANG PHI, va lang phi that:
#   • Moi bat tay TLS deu gui thua ~1KB. Mot API 10.000 ket noi moi/phut thi do
#     la ~600MB/gio bang thong khong ai dung den.
#   • Chuoi dai lam ban tin Certificate vuot qua mot goi TCP -> them mot vong
#     round-trip truoc khi ung dung noi duoc cau dau tien. Tren mang di dong,
#     do la vai chuc mili giay tren MOI ket noi.
#
# ⚠️ Va co mot truong hop no chet that: client tin root A, server gui kem root B
#    (ban cross-sign cu). Mot so thu vien cu duyet chuoi theo dung thu tu server
#    gui, gap root B khong tin duoc thi bao loi thay vi thu duong khac. Do la ly
#    do lich su khien cac su co "AddTrust External CA Root het han 2020" lam
#    sap hang loat he thong con server thi van "binh thuong".
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh

echo "⚠️  MR2 — nginx gui leaf + intermediate + ROOT (thua mot tang)..."
cai_root
dat_chuoi thua-root

buoc "CHU KY: DUNG NHUNG THUA"
in_chu_ky
echo ""
echo "👉 Doc chu ky:"
echo "   • 3 cert tren day thay vi 2. num=0, curl 200 — khong co gi hong."
echo "   • Day la ly do KHONG duoc chan doan bang cau 'chuoi co van de khong?'."
echo "     Phai hoi ro: 'no dut o depth may?'. O day khong dut o dau ca."
echo "   • Chua (neu muon toi uu): bo root khoi file fullchain. Khong gap."
echo ""
echo "   🧠 So sanh nhanh ba kich ban dau:"
echo "        KB2  1 cert  ->  num=20 depth=0  ->  HONG, loi cua SERVER"
echo "        KB1  2 cert  ->  num=0           ->  CHUAN"
echo "        MR2  3 cert  ->  num=0           ->  chay, nhung thua"
