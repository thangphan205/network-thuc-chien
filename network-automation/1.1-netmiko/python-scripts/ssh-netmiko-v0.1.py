from netmiko import ConnectHandler

cisco1 = {
    "device_type": "cisco_ios",
    "host": "192.168.11.11",
    "username": "backup_user",
    "password": "Poothe0uR3Ohziox6mos",
}

net_connect = ConnectHandler(**cisco1)
print(net_connect.find_prompt())
net_connect.disconnect()
