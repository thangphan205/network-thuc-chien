#!/bin/sh
# Sinh chuoi chung chi 3 cap cho Lab 08 moi lan `docker compose up`:
#   Root CA -> Intermediate CA -> Server (app.chain.local)
# Sinh runtime de cert khong bao gio het han voi hoc vien (khong commit cert vao git).
set -eu

OUT=/certs
CN=app.chain.local

cd "$OUT"

# 1. Root CA (nam trong Trust Store cua client)
openssl req -x509 -newkey rsa:2048 -nodes -keyout rootCA.key -out rootCA.crt \
  -subj "/CN=Lab08 Root CA" -days 825

# 2. Intermediate CA (duoc Root ky)
openssl req -newkey rsa:2048 -nodes -keyout intermediateCA.key -out intermediateCA.csr \
  -subj "/CN=Lab08 Intermediate CA"
cat > ca.ext <<'EOF'
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
EOF
openssl x509 -req -in intermediateCA.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial \
  -out intermediateCA.crt -days 825 -extfile ca.ext

# 3. Server cert (duoc Intermediate ky — client PHAI co Intermediate moi noi duoc toi Root)
openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr \
  -subj "/CN=$CN"
printf 'subjectAltName=DNS:%s\n' "$CN" > san.ext
openssl x509 -req -in server.csr -CA intermediateCA.crt -CAkey intermediateCA.key -CAcreateserial \
  -out server_only.crt -days 825 -extfile san.ext

# 4. Fullchain = Server + Intermediate (KHONG kem Root — dung chuan trien khai)
cat server_only.crt intermediateCA.crt > fullchain.crt

rm -f ./*.csr ./*.srl ca.ext san.ext
chmod 644 ./*.crt ./*.key

echo "== Chuoi chung chi da sinh xong =="
openssl verify -CAfile rootCA.crt -untrusted intermediateCA.crt server_only.crt
openssl x509 -in server_only.crt -noout -subject -issuer -dates
