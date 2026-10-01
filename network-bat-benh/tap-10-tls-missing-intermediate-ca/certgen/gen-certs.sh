#!/bin/sh
# ==============================================================================
# Sinh TOAN BO chung chi cua tap 10, moi lan `docker compose up`.
#
#   [Lab10 Root CA]  -->  [Lab10 Intermediate CA]  -->  [app.chain.local]
#
# TU TUONG CUA CA TAP:
#   Client KHONG xac thuc mot cert. No xac thuc mot DUONG DI tu cert cua server
#   ve toi mot cert ma no da tin san. Duong di do co hai doan, va MOI DOAN DUT
#   MOT KIEU KHAC NHAU:
#       doan duoi (leaf -> intermediate) dut  =>  loi o DEPTH 0  =>  SERVER sai
#       doan tren (intermediate -> root)  dut  =>  loi o DEPTH 1  =>  CLIENT sai
#   Ca hai deu in ra DUNG MOT dong chu "unable to get local issuer certificate".
#   Chi con so `depth` tach duoc chung. Do la toan bo bai hoc cua tap 10.
#
# Vi sao sinh runtime ma khong commit cert vao git?
#   Cert commit san se het han that vao mot ngay nao do -> lab thanh "bom hen
#   gio", nam sau hoc vien clone ve la hong ma khong hieu vi sao. Sinh runtime:
#   cert "hop le" luon con han; cert "het han" co notAfter CO DINH trong qua khu.
# ==============================================================================
set -eu

OUT=/certs
TEN=app.chain.local
AIA_URL=http://aia.lab.local/intermediateCA.der

cd "$OUT"
rm -f ./*.crt ./*.key ./*.der ./*.csr ./*.srl ./*.ext 2>/dev/null || true

# Extension dung chung ---------------------------------------------------------
cat > ca.ext <<'EOF'
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
EOF

# Bien the KHONG co pathlen — danh cho ROOT va cho ban CROSS-SIGN.
# pathlen:0 nghia la "CA nay chi duoc ky cert cuoi, khong duoc ky CA khac". Dat
# no len mot ban cross-sign la sai: ban cross-sign nam TREN mot intermediate nua,
# nen chuoi se bi tu choi voi `error 25 path length constraint exceeded` — mot
# ma loi hoan toan khac, lam nhieu dung ca benh MR6 muon day.
cat > caroot.ext <<'EOF'
basicConstraints=critical,CA:TRUE
keyUsage=critical,keyCertSign,cRLSign
EOF

# Leaf that phai co CA:FALSE + EKU serverAuth. iOS/Android TU CHOI cert thieu
# extendedKeyUsage — ma ca tap nay noi ve chuyen "dien thoai bao loi", nen cert
# cua lab phai giong cert that o dung nhung cho do.
cat > leaf.ext <<EOF
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:$TEN
EOF

# Ban sao co them AIA — dung cho MR4.
# caIssuers noi cho client biet TAI DAU de tu tai cert cua nguoi ky ve. Trinh
# duyet doc dong nay va tu va chuoi lai; curl / Java / Python / mobile thi khong.
cat > leaf_aia.ext <<EOF
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:$TEN
authorityInfoAccess=caIssuers;URI:$AIA_URL
EOF

# 1. Root CA — cai vao trust store cua client (0-setup.sh lam viec nay) ---------
openssl req -x509 -newkey rsa:2048 -nodes -keyout rootCA.key -out rootCA.crt \
  -subj "/CN=Lab10 Root CA" -days 825 >/dev/null 2>&1

# 2. Intermediate CA — do Root ky. Mat xich hay bi quen nhat --------------------
openssl req -newkey rsa:2048 -nodes -keyout intermediateCA.key -out intermediateCA.csr \
  -subj "/CN=Lab10 Intermediate CA" >/dev/null 2>&1
openssl x509 -req -in intermediateCA.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial \
  -out intermediateCA.crt -days 825 -extfile ca.ext >/dev/null 2>&1

# Ban DER cho AIA. Chuan RFC 5280 doi caIssuers tra ve DER, khong phai PEM.
openssl x509 -in intermediateCA.crt -outform DER -out intermediateCA.der

# 3. Intermediate CA DA HET HAN — notAfter CO DINH trong qua khu (MR3) ---------
# Leaf do no ky van con han. Do la cai bay: curl bao "certificate has expired",
# ky su di cap lai LEAF, va khong chua duoc gi ca.
openssl req -newkey rsa:2048 -nodes -keyout intHetHan.key -out intHetHan.csr \
  -subj "/CN=Lab10 Intermediate CA (het han)" >/dev/null 2>&1
openssl x509 -req -in intHetHan.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial \
  -out intHetHan.crt -extfile ca.ext \
  -not_before 20200101000000Z -not_after 20240101000000Z >/dev/null 2>&1

# 4. Cac leaf ------------------------------------------------------------------
leaf() {   # leaf <ten_file> <ca_crt> <ca_key> <file_ext>
    openssl req -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1.csr" \
      -subj "/CN=$TEN" >/dev/null 2>&1
    openssl x509 -req -in "$1.csr" -CA "$2" -CAkey "$3" -CAcreateserial \
      -out "$1.crt" -days 825 -extfile "$4" >/dev/null 2>&1
}
leaf server    intermediateCA.crt intermediateCA.key leaf.ext      # KB1,2,3,4,6
leaf serverAia intermediateCA.crt intermediateCA.key leaf_aia.ext  # MR4
leaf serverHH  intHetHan.crt      intHetHan.key      leaf.ext      # MR3

# 4b. MOT CA HOAN TOAN KHAC — dung cho MR5 (ghep nham ca-bundle) ---------------
# Ngoai doi: copy nham file .ca-bundle tu mot site khac trong cung server, hoac
# dan nham doan intermediate trong email cua CA. Server VAN gui du 2 cert — nen
# phep dem cert khong phat hien ra gi ca.
openssl req -x509 -newkey rsa:2048 -nodes -keyout rootKhac.key -out rootKhac.crt \
  -subj "/CN=Root CA cua MOT CA KHAC" -days 825 >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout intKhac.key -out intKhac.csr \
  -subj "/CN=Intermediate cua CA KHAC" >/dev/null 2>&1
openssl x509 -req -in intKhac.csr -CA rootKhac.crt -CAkey rootKhac.key -CAcreateserial \
  -out intKhac.crt -days 825 -extfile ca.ext >/dev/null 2>&1

# 4c. CROSS-SIGN — dung cho MR6 -----------------------------------------------
# Tai hien dung mo hinh da lam sap Internet ngay 30/09/2021 (DST Root CA X3 het
# han) va 30/05/2020 (AddTrust External CA Root het han):
#
#   [rootCu]  DA HET HAN            [rootMoi]  con han
#       \ ky                            |
#        \                              |
#      [crossMoi]  <-- CUNG subject + CUNG khoa cong khai voi rootMoi,
#          |            chi khac o cho AI KY. Day la "ban cross-sign".
#          |
#      [intR3] --> [serverX]
#
# Server gui: serverX + intR3 + crossMoi. Mot chuoi byte DUY NHAT.
#   - May co rootMoi trong store: dung lai o rootMoi, BO QUA crossMoi  -> OK
#   - May chi co rootCu:          phai di het den rootCu da het han    -> HONG
# Cung mot server, cung mot chuoi, hai ket qua nguoc nhau.
openssl req -x509 -newkey rsa:2048 -nodes -keyout rootCu.key -out rootCu.crt \
  -subj "/CN=Lab10 Root CU (het han 2024)" \
  -not_before 20150101000000Z -not_after 20240101000000Z >/dev/null 2>&1
openssl req -x509 -newkey rsa:2048 -nodes -keyout rootMoi.key -out rootMoi.crt \
  -subj "/CN=Lab10 Root MOI" -days 3650 >/dev/null 2>&1

# Ban cross-sign: lay CHINH cert rootMoi, xin rootCu ky lai.
openssl x509 -x509toreq -in rootMoi.crt -signkey rootMoi.key -out cross.csr >/dev/null 2>&1
openssl x509 -req -in cross.csr -CA rootCu.crt -CAkey rootCu.key -CAcreateserial \
  -out crossMoi.crt -days 3650 -extfile caroot.ext >/dev/null 2>&1

openssl req -newkey rsa:2048 -nodes -keyout intR3.key -out intR3.csr \
  -subj "/CN=Lab10 Intermediate R3" >/dev/null 2>&1
openssl x509 -req -in intR3.csr -CA rootMoi.crt -CAkey rootMoi.key -CAcreateserial \
  -out intR3.crt -days 825 -extfile ca.ext >/dev/null 2>&1
leaf serverX intR3.crt intR3.key leaf.ext

# 5. Cac CHUOI ma nginx se gui ra day ------------------------------------------
# Thu tu trong file la thu tu tren day. nginx lay cert DAU TIEN lam cert cua
# server, phan con lai gui kem lam chuoi trung gian.
#
# ⚠️ MOI FILE CHUOI DEU MANG TIEN TO `chuoi_`, VA DAY KHONG PHAI CHUYEN THAM MY.
#    Thu muc nay duoc bind-mount tu may that. macOS (APFS) va Windows deu dung
#    he thong tap tin KHONG PHAN BIET HOA THUONG, nen `inthethan.crt` va
#    `intHetHan.crt` LA CUNG MOT FILE tren may hoc vien — trong khi tren Linux
#    (CI) chung la hai file khac nhau.
#    Neu dat ten trung kieu do thi lenh `cat serverHH.crt intHetHan.crt > inthethan.crt`
#    se doc mot file VAO CHINH NO: shell truncate file dich truoc, roi cat doc
#    mai khong het. Ket qua la mot file phinh vo han cho den khi day o dia — im
#    lang, khong mot thong bao loi nao, va chi xay ra tren macOS/Windows.
#    Tien to `chuoi_` bao dam khong ten chuoi nao trung ten cert theo kieu do.
cat server.crt intermediateCA.crt              > chuoi_daydu.crt      # KB1 — chuan
cp  server.crt                                   chuoi_thieuint.crt   # KB2 — thieu
cat intermediateCA.crt server.crt              > chuoi_daonguoc.crt   # MR1 — sai thu tu
cat server.crt intermediateCA.crt rootCA.crt   > chuoi_thuaroot.crt   # MR2 — thua root
cat serverHH.crt intHetHan.crt                 > chuoi_inthethan.crt  # MR3 — int het han
cp  serverAia.crt                                chuoi_aia.crt        # MR4 — thieu, co AIA
cat server.crt intKhac.crt                     > chuoi_saiint.crt     # MR5 — 2 cert, sai nguoi
cat serverX.crt intR3.crt crossMoi.crt         > chuoi_crosssign.crt  # MR6 — cross-sign

rm -f ./*.csr ./*.srl ./*.ext
chmod 644 ./*.crt ./*.key ./*.der

echo "== Chung chi tap 10 da sinh xong =="
printf '%-18s %s\n' "Root CA"        "$(openssl x509 -in rootCA.crt         -noout -subject | sed 's/^subject=//')"
printf '%-18s %s\n' "Intermediate"   "$(openssl x509 -in intermediateCA.crt -noout -subject | sed 's/^subject=//')"
printf '%-18s %s\n' "Leaf"           "$(openssl x509 -in server.crt         -noout -subject | sed 's/^subject=//')"
echo ""
echo "Kiem tra chuoi day du (phai la OK):"
openssl verify -CAfile rootCA.crt -untrusted intermediateCA.crt server.crt
echo ""
echo "Kiem tra khi THIEU intermediate (phai hong o depth 0):"
openssl verify -CAfile rootCA.crt server.crt 2>&1 || true
