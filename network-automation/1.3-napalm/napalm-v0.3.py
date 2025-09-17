from napalm import get_network_driver


def config_interface_ip():
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
        print("Pushing interface configuration...")

        # Cấu hình IP cho interface (ví dụ: GigabitEthernet1)
        config_commands = [
            "interface E0/2",
            "ip address 192.168.100.12 255.255.255.0",
            "description Configured by NAPALM",
            "no shutdown",
        ]
        config_str = "\n".join(config_commands)

        device.load_merge_candidate(config=config_str)
        diffs = device.compare_config()
        if diffs:
            print("Config diff:")
            print(diffs)
            device.commit_config()
            print("Configuration committed.")
        else:
            print("No changes needed.")
            device.discard_config()
    except Exception as e:
        print(f"Error: {e}")
    finally:
        device.close()


if __name__ == "__main__":
    config_interface_ip()
