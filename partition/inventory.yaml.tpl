---
minilab:
  hosts:
    localhost:
  children:
    leaves:

leaves:
  hosts:
    leaf01:
      ansible_host: "${LEAF01_IP}"
      ansible_ssh_private_key_file: "${LEAF01_PK}"
      lo: 10.0.0.11
      asn: 4200000011
      metal_core_cidr: 10.0.1.1/24
      dhcp_server_net: 10.0.1.0
      dhcp_server_ip: 10.0.1.1
      dhcp_range_min: 10.0.1.2
      dhcp_range_max: 10.0.1.255
    leaf02:
      ansible_host: "${LEAF02_IP}"
      ansible_ssh_private_key_file: "${LEAF02_PK}"
      lo: 10.0.0.12
      asn: 4200000012
      metal_core_cidr: 10.0.1.128/24
  vars:
    ansible_user: vagrant
    ports:
      1: 100G
      2: 100G
    interfaces:
    - name: swp1
    - name: swp2
    uplinks: []
