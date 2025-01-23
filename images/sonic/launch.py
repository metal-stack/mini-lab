#!/usr/bin/python3
import fcntl
import glob
import ipaddress
import json
import logging
import os
import signal
import socket
import struct
import subprocess
import sys
import time

import guestfs
from guestfs import GuestFS

BASE_IMG = '/sonic-vs.img'

VS_DEVICES_PATH = '/usr/share/sonic/device/x86_64-kvm_x86_64-r0/'


class Qemu:
    def __init__(self, name: str, smp: str, memory: str):
        self._name = name
        self._smp = smp
        self._memory = memory
        self._p = None
        self._disk = '/overlay.img'

    def prepare_overlay(self, base: str) -> None:
        cmd = [
            'qemu-img',
            'create',
            '-f', 'qcow2',
            '-F', 'qcow2',
            '-b', base,
            self._disk,
        ]
        subprocess.run(cmd, check=True)

    def guestfs(self) -> GuestFS:
        g = guestfs.GuestFS(python_return_dict=True)
        g.add_drive_opts(filename=self._disk, format="qcow2", readonly=False)
        g.launch()
        g.mount('/dev/sda3', '/')
        return g

    def start(self) -> None:
        cmd = [
            'qemu-system-x86_64',
            '-cpu', 'host',
            '-smp', self._smp,
            '-display', 'none',
            '-enable-kvm',
            '-nodefaults',
            '-machine', 'q35',
            '-name', self._name,
            '-m', self._memory,
            '-drive', f'if=virtio,format=qcow2,file={self._disk}',
            '-serial', 'telnet:127.0.0.1:5000,server,nowait',
        ]

        with open(f'/sys/class/net/eth0/address', 'r') as f:
            mac = f.read().strip()
        cmd.append('-device')
        cmd.append(f'virtio-net-pci,netdev=hn0,mac={mac}')
        cmd.append(f'-netdev')
        cmd.append(f'tap,id=hn0,ifname=tap0,script=/mirror_tap_to_eth.sh,downscript=no')

        ifaces = get_ethernet_interfaces()
        for i, iface in enumerate(ifaces, start=1):
            with open(f'/sys/class/net/{iface}/address', 'r') as f:
                mac = f.read().strip()
            cmd.append('-device')
            cmd.append(f'virtio-net-pci,netdev=hn{i},mac={mac}')
            cmd.append(f'-netdev')
            cmd.append(f'tap,id=hn{i},ifname=tap{i},script=/mirror_tap_to_front_panel.sh,downscript=no')

        self._p = subprocess.Popen(cmd)

    def wait(self) -> None:
        self._p.wait()


def initial_configuration(g: GuestFS, hwsku: str) -> None:
    image = g.glob_expand('/image-*')[0]

    g.rm(image + 'platform/firsttime')

    systemd_system = image + 'rw/etc/systemd/system/'
    sonic_target_wants = systemd_system + 'sonic.target.wants/'
    g.mkdir_p(sonic_target_wants)

    # Copy frr-pythontools into the image
    g.copy_in(localpath='/frr-pythontools.deb', remotedir=image + 'rw/')

    # Workaround: Speed up lldp startup by remove hardcoded wait of 90 seconds
    g.ln_s(linkname=systemd_system + 'aaastatsd.timer', target='/dev/null') # Radius
    g.ln_s(linkname=systemd_system + 'featured.timer', target='/dev/null') # Feature handling not necessary
    g.ln_s(linkname=systemd_system + 'hostcfgd.timer', target='/dev/null') # After boot Host configuration
    g.ln_s(linkname=systemd_system + 'rasdaemon.timer', target='/dev/null') # After boot Host configuration
    g.ln_s(linkname=systemd_system + 'tacacs-config.timer', target='/dev/null') # After boot Host configuration
    # Started by featured
    g.ln_s(linkname=sonic_target_wants + 'lldp.service', target='/lib/systemd/system/lldp.service')
    g.ln_s(linkname=systemd_system + 'pmon.service', target='/lib/systemd/system/pmon.service')
    g.ln_s(linkname=sonic_target_wants + 'pmon.service', target='/lib/systemd/system/pmon.service')

    # Workaround: Only useful for BackEndToRRouter
    g.ln_s(linkname=systemd_system + 'backend-acl.service', target='/dev/null')

    # Workaround: We don't need LACP
    g.ln_s(linkname=systemd_system + 'teamd.service', target='/dev/null')

    # Workaround: Python module sonic_platform not present on vs images
    g.ln_s(linkname=systemd_system + 'system-health.service', target='/dev/null')
    g.ln_s(linkname=systemd_system + 'watchdog-control.service', target='/dev/null')

    sonic_share = image + 'rw/usr/share/sonic/'
    hwsku_dir = image + 'rw' + VS_DEVICES_PATH + hwsku
    g.mkdir_p(hwsku_dir)

    g.write(path=image + 'rw' + VS_DEVICES_PATH + 'default_sku', content=f'{hwsku} empty'.encode('utf-8'))
    g.ln_s(linkname=sonic_share + 'hwsku', target=VS_DEVICES_PATH + hwsku)
    g.ln_s(linkname=sonic_share + 'platform', target=VS_DEVICES_PATH)

    ifaces = get_ethernet_interfaces()
    # The port_config.ini file contains the assignment of front panels to lanes.
    port_config = parse_port_config()
    # The lanemap.ini file is used by the virtual switch image to assign front panels to the Linux interfaces ethX.
    # This assignment will later also be used by the script mirror_tap_to_front_panel.sh.
    lanemap = create_lanemap(port_config, ifaces)
    with open('/lanemap.ini', 'w') as f:
        f.write('\n'.join(lanemap))

    g.copy_in(localpath='/lanemap.ini', remotedir=hwsku_dir)
    g.copy_in(localpath='/port_config.ini', remotedir=hwsku_dir)

    etc_sonic = image + 'rw/etc/sonic/'
    g.mkdir_p(etc_sonic)
    sonic_version = image.removeprefix('/image-').removesuffix('/')
    sonic_environment = f'''
        SONIC_VERSION=${sonic_version}
        PLATFORM=x86_64-kvm_x86_64-r0
        HWSKU={hwsku}
        DEVICE_TYPE=LeafRouter
        ASIC_TYPE=vs
        '''.encode('utf-8')
    g.write(path=etc_sonic + 'sonic-environment', content=sonic_environment)

    config_db = create_config_db(hwsku)
    ports = {}
    for iface in ifaces:
        ports[iface] = {
            **port_config[iface],
            'admin_status': 'up',
            'mtu': '9100'
        }
    config_db['PORT'] = ports
    config_db_json = json.dumps(config_db, indent=4, sort_keys=True)

    g.write(path=etc_sonic + 'config_db.json', content=config_db_json.encode('utf-8'))

    if os.path.exists('/authorized_keys'):
        g.mkdir_p(image + 'rw/root/.ssh')
        g.chmod(mode=0x0600, path=image + 'rw/root/.ssh')
        g.copy_in(localpath='/authorized_keys', remotedir=image + 'rw/root/.ssh/')
        g.chown(owner=0, group=0, path=image + 'rw/root/.ssh/authorized_keys')


def main():
    signal.signal(signal.SIGINT, handle_exit)
    signal.signal(signal.SIGTERM, handle_exit)

    logging.basicConfig(level=logging.INFO, stream=sys.stdout)
    logger = logging.getLogger()

    name = os.getenv('CLAB_LABEL_CLAB_NODE_NAME', default='switch')
    smp = os.getenv('QEMU_SMP', default='2')
    memory = os.getenv('QEMU_MEMORY', default='2048')
    interfaces = int(os.getenv('CLAB_INTFS', 0)) + 1
    hwsku = os.getenv('HWSKU', default='Accton-AS7726-32X')

    vm = Qemu(name, smp, memory)

    logger.info('Prepare disk')
    vm.prepare_overlay(BASE_IMG)

    logger.info(f'Waiting for {interfaces} interfaces to be connected')
    wait_until_all_interfaces_are_connected(interfaces)

    logger.info('Deploy initial config')
    g = vm.guestfs()
    initial_configuration(g, hwsku)
    g.shutdown()
    g.close()

    logger.info('Start QEMU')
    vm.start()

    logger.info('Wait until QEMU is terminated')
    vm.wait()


def handle_exit(signal, frame):
    sys.exit(0)


def wait_until_all_interfaces_are_connected(interfaces: int) -> None:
    while True:
        i = 0
        for iface in os.listdir('/sys/class/net/'):
            if iface.startswith('eth') or iface.startswith('Ethernet'):
                i += 1
        if i == interfaces:
            break
        time.sleep(1)


def get_ip_address(iface: str) -> str:
    # Source: https://bit.ly/3dROGBN
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    return socket.inet_ntoa(fcntl.ioctl(
        s.fileno(),
        0x8915,  # SIOCGIFADDR
        struct.pack('256s', iface.encode('utf_8'))
    )[20:24])


def get_netmask(iface: str) -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    # Use ioctl to get the netmask
    netmask = socket.inet_ntoa(fcntl.ioctl(
        s.fileno(),
        0x891b,  # SIOCGIFNETMASK
        struct.pack('256s', iface.encode('utf-8'))
    )[20:24])
    return str(ipaddress.ip_network(f"0.0.0.0/{netmask}").prefixlen)


def get_mac_address(iface: str) -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    mac = fcntl.ioctl(
        s.fileno(),
        0x8927,  # SIOCGIFHWADDR
        struct.pack('256s', iface.encode('utf-8'))
    )[18:24]
    return ':'.join('%02x' % b for b in mac)


def get_default_gateway() -> str:
    # Source: https://splunktool.com/python-get-default-gateway-for-a-local-interfaceip-address-in-linux
    with open("/proc/net/route") as fh:
        for line in fh:
            fields = line.strip().split()
            if fields[1] != '00000000' or not int(fields[3], 16) & 2:
                # If not default route or not RTF_GATEWAY, skip it
                continue
            return socket.inet_ntoa(struct.pack("<L", int(fields[2], 16)))


def get_ethernet_interfaces() -> list[str]:
    ethernet_dirs = glob.glob('/sys/class/net/Ethernet*')
    ifaces = [os.path.basename(dir) for dir in ethernet_dirs]
    ifaces.sort()
    return ifaces


def create_lanemap(port_config: dict[str, dict], ifaces: list[str]) -> list[str]:
    lanemap = []

    for i, iface in enumerate(ifaces, start=1):
        lanes = port_config[iface]['lanes']
        lanemap.append(f'eth{i}:{lanes}')

    return lanemap


def parse_port_config() -> dict[str, dict]:
    with open('/port_config.ini', 'r') as file:
        lines = file.readlines()

    port_config = {}

    for line in lines[1:]:
        columns = line.split()
        name = columns[0]
        port_config[name] = {
            "lanes": columns[1],
            "alias": columns[2],
            "index": columns[3],
            "speed": columns[4],
        }

    return port_config


def create_config_db(hwsku: str) -> dict:
    mgmt_interface_cidr = get_ip_address("eth0") + "/" + get_netmask("eth0")
    return {
        'AUTO_TECHSUPPORT': {
            'GLOBAL': {
                'state': 'disabled'
            }
        },
        'DEVICE_METADATA': {
            'localhost': {
                'docker_routing_config_mode': 'split-unified',
                'hostname': socket.gethostname(),
                'hwsku': hwsku,
                'mac': get_mac_address('eth0'),
                'platform': 'x86_64-kvm_x86_64-r0',
                'type': 'LeafRouter',
            }
        },
        'FEATURE': {
            'gnmi': {
                'state': 'disabled'
            },
            'mgmt-framework': {
                'state': 'disabled'
            },
            'snmp': {
                'state': 'disabled'
            },
            'teamd': {
                'state': 'disabled'
            }
        },
        'MGMT_INTERFACE': {
            f'eth0|{mgmt_interface_cidr}': {
                'gwaddr': get_default_gateway(),
            }
        },
        'MGMT_PORT': {
            'eth0': {
                'alias': 'eth0',
                'admin_status': 'up'
            }
        },
        'VERSIONS': {
            'DATABASE': {
                'VERSION': 'version_202311_03'
            }
        }
    }


if __name__ == '__main__':
    main()
