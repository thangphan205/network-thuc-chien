import netmiko
import yaml
import os

# --- Configuration ---
DEVICES_FILE = "devices.yml"
BACKUP_DIR = "backup-files"


# --- Main Script Logic ---
def backup_network_devices():
    """Reads devices from a YAML file, connects, and backs up configurations."""

    # 2. Ensure the backup directory exists
    if not os.path.exists(BACKUP_DIR):
        os.makedirs(BACKUP_DIR)
        print(f"Created directory: {BACKUP_DIR}")

    # 3. Read the devices from the YAML file
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
        device_type = device_info.get("device_type")

        print(f"\n--- Starting backup for {hostname} ({device_type}) ---")

        try:
            # Netmiko's ConnectHandler takes care of SSH connection
            with netmiko.ConnectHandler(**device_info) as net_connect:

                # --- FIX: Set the correct backup command based on device_type ---
                if "junos" in device_type:
                    # Juniper uses 'show configuration | display set' to get a
                    # readable configuration that can be used for restoring.
                    command = "show configuration | display set"
                else:
                    # Cisco IOS, Arista EOS, etc., use this command.
                    command = "show running-config"

                output = net_connect.send_command(command)

                # Use 'find_prompt' to get the device's hostname dynamically
                device_prompt = net_connect.find_prompt()
                device_hostname = (
                    device_prompt.replace("#", "").replace(">", "").strip()
                )

                # For Juniper, the prompt can sometimes have the user and master/backup
                # information, so we'll do a little extra cleaning.
                if "junos" in device_type:
                    device_hostname = device_hostname.split("@")[-1].split(" ")[0]

                # 5. Save the configuration to a timestamped file
                backup_filename = f"ssh-netmiko-v1.1_{device_hostname}.cfg"
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
