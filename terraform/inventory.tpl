[openvpn_servers]
${server_name} ansible_host=${server_ip} ansible_user=${ssh_user} ansible_ssh_private_key_file=${ssh_key} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ConnectTimeout=30'

[openvpn_servers:vars]
ansible_python_interpreter=/usr/bin/python3
