FROM alpine:3.23
# ==============================================================================
# MAY CLIENT — "nan nhan" cua tap 10.
#
# Cong cu va vi sao can tung cai:
#   openssl         — doc CHUOI server gui ra day (`s_client -showcerts`) va lay
#                     ma verify KEM SO DEPTH. Con so depth la truc chinh cua tap.
#   curl            — goc nhin cua UNG DUNG. Khac trinh duyet o dung mot diem
#                     quyet dinh: curl KHONG di tai AIA. Do la ca benh MR4.
#   ca-certificates — de CAI / GO root CA cua lab khoi trust store. KB3 song
#                     bang chinh thao tac go nay.
#   tcpdump         — do kich thuoc ban tin Certificate giua cac kich ban.
#
#   nodejs / python3 / java — MR7. Ba runtime nay KHONG dung trust store cua he
#                     dieu hanh, moi thang mot kieu. Do la ly do ngoai doi ban
#                     nghe "Chrome duoc, Java chet, Python chet" tren CUNG mot
#                     server. Khong co chung trong image thi ca benh pho bien
#                     nhat cua doanh nghiep khong the dien lai duoc.
#
# ⚠️ KHONG dinh --cacert vao moi lenh curl trong lab nay. Ngoai doi CA nam trong
#    trust store va lenh la `curl https://host/` tran. Neu bat hoc vien go
#    --cacert thi KB3 (thieu root o client) se bien mat hoan toan — no chinh la
#    ca benh "trust store thieu CA", ma --cacert lai vua vo tinh chua no.
# ==============================================================================
RUN apk add --no-cache curl openssl ca-certificates tcpdump \
                       nodejs python3 py3-requests py3-certifi \
                       openjdk17-jre-headless

COPY monitor.sh /usr/local/bin/monitor.sh
RUN chmod 0755 /usr/local/bin/monitor.sh

CMD ["sleep", "infinity"]
