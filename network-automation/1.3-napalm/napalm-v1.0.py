from napalm import get_network_driver
import json
from datetime import datetime


def get_device_info():
    # Initialize the network driver for Cisco IOS
    driver = get_network_driver("ios")

    # Device connection parameters
    device = driver(
        hostname="192.168.11.11",  # Thay bằng địa chỉ IP thiết bị của bạn
        username="backup_user",  # Thay bằng username của bạn
        password="Poothe0uR3Ohziox6mos",  # Thay bằng password của bạn
        optional_args={"secret": "enable_pass"},  # Optional: enable password
    )

    # Create a dictionary to store all device information
    device_info = {}

    try:
        print("Connecting to device...")
        device.open()

        # Collect device information
        print("Gathering device information...")

        # Get basic facts
        device_info["facts"] = device.get_facts()

        # Get interfaces
        device_info["interfaces"] = device.get_interfaces()

        # Get interface IP addresses
        device_info["interfaces_ip"] = device.get_interfaces_ip()

        # Get LLDP neighbors
        device_info["lldp_neighbors"] = device.get_lldp_neighbors()

        # Get ARP table
        device_info["arp_table"] = device.get_arp_table()

        # Get MAC address table
        device_info["mac_address_table"] = device.get_mac_address_table()

        # Generate filename with timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"switch_info_{timestamp}.json"

        # Save information to file
        with open(filename, "w") as f:
            json.dump(device_info, f, indent=4)

        print(f"Device information saved to {filename}")

    except Exception as e:
        print(f"An error occurred: {e}")

    finally:
        print("Closing connection...")
        device.close()


if __name__ == "__main__":
    get_device_info()
