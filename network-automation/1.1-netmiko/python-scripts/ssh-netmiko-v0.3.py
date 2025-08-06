from netmiko import ConnectHandler

cisco1 = {
    "device_type": "cisco_ios",
    "host": "192.168.11.11",
    "username": "backup_user",
    "password": "Poothe0uR3Ohziox6mos",
}

net_connect = ConnectHandler(**cisco1)
commands = [
    "int e0/1",
    "ip address 192.168.1.10 255.255.255.0",
    "description Test Interface",
]
output = net_connect.send_config_set(commands)
print(output)
net_connect.disconnect()
print("--- Script completed successfully ---")
