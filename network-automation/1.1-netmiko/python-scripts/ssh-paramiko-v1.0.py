import paramiko
import os
import time

# --- Configuration ---
# Use environment variables or a secrets manager for credentials.
# DO NOT hard-code them in a production script.
# For this PoC, you can set them here.
SSH_USERNAME = "backup_user"  # Replace with your SSH username
SSH_PASSWORD = "Poothe0uR3Ohziox6mos"  # Or use SSH keys for better security

# The file containing the list of devices
# DEVICES_FILE = "devices.txt"
NETWORK_DEVICES = ["192.168.11.11", "192.168.11.12", "192.168.11.13"]
# The directory to store the backups
BACKUP_DIR = "backup-files"


# --- Function to backup a single device ---
def backup_device_config(hostname, username, password):
    """Connects to a device and saves its running configuration."""
    try:
        # Create an SSH client
        ssh_client = paramiko.SSHClient()

        # This policy is not secure for production. It accepts any key from the server.
        # In production, you should use ssh_client.load_system_host_keys() or similar.
        ssh_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

        print(f"Connecting to {hostname}...")
        ssh_client.connect(
            hostname=hostname, username=username, password=password, timeout=10
        )
        print(f"Successfully connected to {hostname}.")

        # Invoke a shell to send commands
        shell = ssh_client.invoke_shell()

        # Give the shell time to initialize
        time.sleep(1)

        # Disable pagination (for Cisco IOS)
        shell.send("terminal length 0\n")
        time.sleep(1)

        # Send the command to show the running configuration
        shell.send("show running-config\n")
        time.sleep(5)  # Wait for the command to execute and the output to be sent

        # Read the output from the shell
        output = shell.recv(65535).decode("utf-8")

        # Close the SSH connection
        ssh_client.close()

        # --- Save the configuration to a file ---
        backup_filename = f"ssh-paramiko-v1.0_{hostname}.cfg"
        backup_path = os.path.join(BACKUP_DIR, backup_filename)

        with open(backup_path, "w") as f:
            f.write(output)

        print(f"Backup saved to {backup_path}")

    except paramiko.AuthenticationException:
        print(f"Authentication failed for {hostname}. Please check credentials.")
    except paramiko.SSHException as ssh_e:
        print(f"SSH error on {hostname}: {ssh_e}")
    except Exception as e:
        print(f"An unexpected error occurred for {hostname}: {e}")


# --- Main Script Logic ---
if __name__ == "__main__":
    # Ensure the backup directory exists
    if not os.path.exists(BACKUP_DIR):
        os.makedirs(BACKUP_DIR)
        print(f"Created directory: {BACKUP_DIR}")

    try:
        for device in NETWORK_DEVICES:
            backup_device_config(device, SSH_USERNAME, SSH_PASSWORD)
            print("-" * 30)  # Separator for readability

    except Exception as e:
        print(f"Error: {e}")
