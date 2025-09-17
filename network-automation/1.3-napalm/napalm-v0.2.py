from napalm import get_network_driver
from pprint import pprint


def show_config():
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
        output = device.cli(["show running-config"])
        print(output["show running-config"])
        with open("running-config.txt", "w") as f:
            f.write(output["show running-config"])
    except Exception as e:
        print(f"Error: {e}")
    finally:
        device.close()


if __name__ == "__main__":
    show_config()
