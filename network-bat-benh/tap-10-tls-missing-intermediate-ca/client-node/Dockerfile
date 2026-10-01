FROM node:22-slim
# ==============================================================================
# CLIENT THU HAI — mot may DEBIAN, dung image chinh thuc cua Node.
#
# Vi sao lab can HAI may client?
#   Vi bai hoc cua MR7 khong phai "Node khong tin CA cua ban". Ma la:
#   CUNG MOT root CA, CUNG MOT lenh cai, HAI IMAGE cho HAI KET QUA.
#
#   - lab10-client      (Alpine): apk ca-certificates noi HET moi runtime ve
#     trust store cua he dieu hanh — no con sinh lai ca `/etc/ssl/certs/java/cacerts`
#     cho Java. Cai CA mot lan la curl / node / python / java deu thay.
#   - lab10-client-node (Debian + image node chinh thuc): Node mang THEO danh
#     sach CA rieng nen trong binary. `update-ca-certificates` chay thanh cong,
#     curl thay CA ngay, ma Node van khong thay gi.
#
#   Nghia la cau hoi "cai CA vao trust store xong chua?" KHONG du. Phai hoi:
#   "runtime nay co doc trust store do khong?"
#
# ⚠️ ca-certificates va curl KHONG co san trong node:22-slim. Thieu chung thi
#    `update-ca-certificates` bao loi va phep thu tro nen khong cong bang —
#    Node se hong vi may chua he co CA, chu khong phai vi Node bo qua CA.
# ==============================================================================
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl openssl \
 && rm -rf /var/lib/apt/lists/*

CMD ["sleep", "infinity"]
