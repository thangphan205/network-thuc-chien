from napalm import get_network_driver


def show_version():
    driver = get_network_driver("ios")
    device = driver(
        hostname="192.168.11.11",  # Thay bằng địa chỉ IP thiết bị của bạn
        username="backup_user",  # Thay bằng username của bạn
        password="Poothe0uR3Ohziox6mos",  # Thay bằng password của bạn
        optional_args={"secret": "enable_pass"},  # Nếu có enable password
    )
    try:
        print("Connecting to device...")
        device.open()
        print("Getting 'show version' output...")
        output = device.cli(["show ip int brief"])
        print(output["show ip int brief"])
        with open("device_config.txt", "w") as f:
            f.write(output["show ip int brief"])
        with open("show_ip.txt", "w") as f2:
            f2.write(output["show ip int brief"])
    except Exception as e:
        print(f"Error: {e}")
    finally:
        device.close()


if __name__ == "__main__":
    show_version()
