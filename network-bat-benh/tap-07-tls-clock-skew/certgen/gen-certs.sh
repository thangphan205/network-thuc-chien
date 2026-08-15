#!/bin/sh
# Sinh toan bo chung chi cho Lab 07 moi lan `docker compose up`.
# Cert "expired" co notAfter co dinh trong qua khu (01/01/2024) nen lab
# khong bao gio bi "bom hen gio" du hoc vien chay lab vao nam nao.
set -eu

OUT=/certs
CN=secure.local

cd "$OUT"

# 1. Root CA cua lab
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt \
  -subj "/CN=Lab07 Root CA" -days 825

# 2. Chung chi HOP LE cho secure.local (dung o buoc chua benh)
openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr \
  -subj "/CN=$CN"
printf 'subjectAltName=DNS:%s\n' "$CN" > san.ext
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -days 825 -extfile san.ext

# 3. Chung chi DA HET HAN (notAfter = 01/01/2024) — dung de kich hoat ca benh
openssl req -newkey rsa:2048 -nodes -keyout expired.key -out expired.csr \
  -subj "/CN=$CN"
openssl x509 -req -in expired.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out expired.crt -extfile san.ext \
  -not_before 20230101000000Z -not_after 20240101000000Z

rm -f server.csr expired.csr san.ext ca.srl
# nginx worker (user nginx) can doc duoc key trong pham vi lab
chmod 644 ./*.crt ./*.key

echo "== Chung chi da sinh xong =="
openssl x509 -in server.crt  -noout -subject -dates
openssl x509 -in expired.crt -noout -subject -dates
