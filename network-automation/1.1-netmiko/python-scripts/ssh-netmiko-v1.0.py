import netmiko
import yaml
import os

# --- Configuration ---
DEVICES_FILE = "devices.yml"
BACKUP_DIR = "backup-files"


# --- Main Script Logic ---
def backup_network_devices():
    """Reads devices from a YAML file, connects, and backs up configurations."""

    # Ensure the backup directory exists
    if not os.path.exists(BACKUP_DIR):
        os.makedirs(BACKUP_DIR)
        print(f"Created directory: {BACKUP_DIR}")

    # Read the devices from the YAML file
    try:
        with open(DEVICES_FILE, "r") as f:
            devices = yaml.safe_load(f)
    except FileNotFoundError:
        print(f"Error: The devices file '{DEVICES_FILE}' was not found.")
        return
    except yaml.YAMLError as e:
        print(f"Error parsing YAML file: {e}")
        return

    # 4. Iterate through each device and perform the backup
    for device_info in devices:
        hostname = device_info.get("host")

        print(f"\n--- Starting backup for {hostname} ---")

        try:
            # Netmiko's ConnectHandler takes care of SSH connection and command execution
            with netmiko.ConnectHandler(**device_info) as net_connect:
                # The 'send_command' method handles pagination automatically.
                # 'show running-config' is the standard command for many vendors.
                # For Cisco ASA, it's 'show running-config'.
                # For Juniper, it's 'show configuration | display set'.
                # Netmiko handles this logic based on device_type.
                command = "show running-config"
                if "arista" in device_info["device_type"]:
                    net_connect.enable()
                    command = "show running-config"
                elif "juniper" in device_info["device_type"]:
                    command = "show configuration | display set"

                output = net_connect.send_command(command)

                # Use 'find_prompt' to get the device's hostname dynamically
                # This makes the filename more useful.
                device_prompt = net_connect.find_prompt()
                device_hostname = device_prompt.replace("#", "").replace(">", "")

                # Save the configuration to a timestamped file
                backup_filename = f"ssh-netmiko-v1.0_{device_hostname}.cfg"
                backup_path = os.path.join(BACKUP_DIR, backup_filename)

                with open(backup_path, "w") as f:
                    f.write(output)

                print(f"Backup for {device_hostname} saved to {backup_path}")

        except netmiko.NetmikoAuthenticationException:
            print(f"Authentication failed for {hostname}. Skipping.")
        except netmiko.NetmikoTimeoutException:
            print(f"Connection timed out for {hostname}. Skipping.")
        except Exception as e:
            print(f"An unexpected error occurred for {hostname}: {e}")


# --- Execute the script ---
if __name__ == "__main__":
    backup_network_devices()
# This script uses Netmiko to connect to network devices and back up their configurations.
# It reads device details from a YAML file, connects to each device, retrieves the running configuration,
# and saves it to a file in a specified backup directory. The script handles errors gracefully and
# ensures that the backup directory exists before proceeding with the backups.
