#!/usr/bin/python3
# Taken from https://raw.githubusercontent.com/cminyard/openipmi/refs/heads/master/lanserv/ipmi_sim_lancontrol
#
# An example script for handling external LAN configuration from the
# IPMI simulator.  This command is generally invoked by the IPMI
# simulator to get and set external LAN configuration parameters.
#
# It's parameters are:
#
#  ipmi_sim_lancontrol <device> get [parm [parm ...]]
#  ipmi_sim_lancontrol <device> set|check [parm val [parm val ...]]
#
# where <device> is a network device (eth0, etc.) and parm is one of:
#  ip_addr
#  ip_addr_src
#  mac_addr
#  subnet_mask
#  default_gw_ip_addr
#  default_gw_mac_addr
#  backup_gw_ip_addr
#  backup_gw_mac_addr
# These are config values out of the IPMI LAN config table that are
# not IPMI-exclusive, they require setting external things.
#
# The output of the "get" is "<parm>:<value>" for each listed parm.
# The output of the "set" is empty on success.  Error output goes to
# standard out (so it can be captured in the simulator) and the program
# returns an error.
#
# The IP address values are standard IP addresses in the form a.b.c.d.
# The MAC addresses ar standard 6 octet xx:xx:xx:xx:xx:xx values.  The
# only special one is ip_addr_src, which can be "dhcp" or "static".
#
# The "check" operation checks to see if a value is valid without
# committing it.  It is only implemented for the ip_addr_src parm.
#

import fcntl
import socket
import struct
import sys


def do_get(device, parameters):
    for param in parameters:
        if param == 'ip_addr':
            val = get_ip_address(device)
            val = val if val else '0.0.0.0'
        elif param == 'ip_addr_src':
            val = 'static' # maybe 'dhcp'
        elif param == 'mac_addr':
            val = get_mac_address(device)
            val = val if val else '00:00:00:00'
        elif param == 'subnet_mask':
            val = get_subnet_mask(device)
            val = val if val else '0.0.0.0'
        elif param == 'default_gw_ip_addr':
            val = get_default_gateway_ip_address()
            val = val if val else '0.0.0.0'
        elif param == 'default_gw_mac_addr':
            gateway_ip = get_default_gateway_ip_address()
            if gateway_ip:
                val = get_default_gateway_mac_address(gateway_ip)
                val = val if val else '00:00:00:00:00:00'
            else:
                val = '00:00:00:00:00:00'
        elif param == 'backup_gw_ip_addr':
            val = '0.0.0.0'
        elif param == 'backup_gw_mac_addr':
            val = '00:00:00:00:00:00'
        else:
            print(f"Invalid parameter: {param}")
            sys.exit(1)

        print(f"{param}:{val}")


def get_ip_address(iface: str) -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    return socket.inet_ntoa(fcntl.ioctl(
        s.fileno(),
        0x8915,  # SIOCGIFADDR
        struct.pack('256s', iface.encode('utf8'))
    )[20:24])


def get_mac_address(iface: str) -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    mac = fcntl.ioctl(
        s.fileno(),
        0x8927,  # SIOCGIFHWADDR
        struct.pack('256s', iface.encode('utf8'))
    )[18:24]
    return ':'.join('%02x' % b for b in mac)


def get_subnet_mask(iface):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    netmask = fcntl.ioctl(
        s.fileno(),
        0x891b,  # SIOCGIFNETMASK
        struct.pack('256s', iface.encode('utf8'))
    )[20:24]
    return socket.inet_ntoa(netmask)


def get_default_gateway_ip_address() -> str:
    with open('/proc/net/route') as fh:
        for line in fh:
            fields = line.strip().split()
            if fields[1] != '00000000' or not int(fields[3], 16) & 2:
                # If not default route or not RTF_GATEWAY, skip it
                continue
            return socket.inet_ntoa(struct.pack('<L', int(fields[2], 16)))


def get_default_gateway_mac_address(gateway_ip: str):
    with open('/proc/net/arp', 'r') as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            if fields[0] == gateway_ip:
                return fields[3]


def do_set(parameters):
    if len(parameters) % 2 != 0:
        print('Parameter and value pairs are required.')
        sys.exit(1)

    for i in range(0, len(parameters), 2):
        param, val = parameters[i], parameters[i + 1]
        if param not in ['ip_addr', 'ip_addr_src', 'mac_addr', 'subnet_mask',
                         'default_gw_ip_addr', 'default_gw_mac_addr',
                         'backup_gw_ip_addr', 'backup_gw_mac_addr']:
            print(f"Invalid parameter: {param}")
            sys.exit(1)


def do_check(parameters):
    for param in parameters:
        if param == 'ip_addr_src':
            value = parameters[1]
            if value not in ['static', 'dhcp']:
                print(f"Invalid ip_addr_src: {value}")
                sys.exit(1)
        else:
            print(f"Invalid parameter: {param}")
            sys.exit(1)


def main():
    if len(sys.argv) < 3:
        print('Usage: lancontrol.py <device> <operation> [parameters...]')
        sys.exit(1)

    device = sys.argv[1]
    operation = sys.argv[2]
    parameters = sys.argv[3:]

    if operation == 'get':
        do_get(device, parameters)
    elif operation == 'set':
        do_set(parameters)
    elif operation == 'check':
        do_check(parameters)
    else:
        print(f"Unknown operation: {operation}")
        sys.exit(1)


if __name__ == '__main__':
    main()
