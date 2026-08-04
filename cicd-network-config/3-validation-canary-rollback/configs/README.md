Thư mục này chứa config export từ thiết bị (input cho `batfish_check.py`), ví dụ:

```bash
docker exec clab-cicd_validation_lab-canary1 vtysh -c "show running-config" > configs/canary1.cfg
docker exec clab-cicd_validation_lab-node2 vtysh -c "show running-config" > configs/node2.cfg
docker exec clab-cicd_validation_lab-node3 vtysh -c "show running-config" > configs/node3.cfg
```

Không commit config export thật vào Git — thư mục này chỉ để trống làm placeholder.
