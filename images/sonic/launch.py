#!/usr/bin/python3
import fcntl
import glob
import json
import logging
import os
import shutil
import signal
import socket
import struct
import subprocess
import sys
import time

BASE_IMG = '/sonic-vs.img'
FUSE_PATH = '/mnt/sonic.img'


class Qemu:
    def __init__(self, name: str, smp: str, memory: str, interfaces: int):
        self._name = name
        self._smp = smp
        self._memory = memory
        self._interfaces = interfaces
        self._fuse = None
        self._nbd = None
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

    def mount(self, path: str):
        self._nbd = subprocess.Popen(['qemu-nbd', '--socket', '/nbd.sock', self._disk])

        nbdkit = ['nbdkit', '--single', 'nbd', 'socket=/nbd.sock', '--filter=partition', 'partition=3']
        self._fuse = subprocess.Popen(['nbdfuse', FUSE_PATH, '--command'] + nbdkit)

        while not os.path.exists(FUSE_PATH):
            if self._nbd.poll() is not None:
                print('qemu-nbd terminated with exit code ' + self._nbd.returncode)
                exit(1)
            if self._fuse.poll() is not None:
                print('nbdfuse terminated with exit code ' + self._fuse.returncode)
                exit(1)
            print("Waiting for file to exist...")
            time.sleep(1)

        subprocess.run(['fuse2fs', '-o', 'fakeroot', FUSE_PATH, path], check=True)

    def umount(self, path: str):
        subprocess.run(['fusermount', '-u', path], check=True)

        self._fuse.terminate()
        self._fuse.wait(timeout=10)

        self._nbd.terminate()
        self._nbd.wait(timeout=10)

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

        for i in range(self._interfaces):
            with open(f'/sys/class/net/eth{i}/address', 'r') as f:
                mac = f.read().strip()
            cmd.append('-device')
            cmd.append(f'virtio-net-pci,netdev=hn{i},mac={mac}')
            cmd.append(f'-netdev')
            cmd.append(f'tap,id=hn{i},ifname=tap{i},script=/mirror_tap_to_eth.sh,downscript=no')

        self._p = subprocess.Popen(cmd)

    def wait(self) -> None:
        self._p.wait()


def initial_configuration(path: str) -> None:
    image = glob.glob(os.path.join(path, 'image-*'))[0]

    os.remove(os.path.join(image, 'platform/firsttime'))

    systemd_system = os.path.join(image, 'rw/etc/systemd/system/')
    sonic_target_wants = os.path.join(systemd_system, 'sonic.target.wants/')
    os.makedirs(sonic_target_wants, exist_ok=True)

    # Copy frr-pythontools into the image
    shutil.copy('/frr-pythontools.deb', os.path.join(image, 'rw/'))

    # Workaround: Speed up lldp startup by remove hardcoded wait of 90 seconds
    os.symlink('/dev/null', os.path.join(systemd_system, 'aaastatsd.timer'))  # Radius
    os.symlink('/dev/null', os.path.join(systemd_system, 'featured.timer'))  # Feature handling not necessary
    os.symlink('/dev/null', os.path.join(systemd_system, 'hostcfgd.timer'))  # After boot Host configuration
    os.symlink('/dev/null', os.path.join(systemd_system, 'rasdaemon.timer'))  # After boot Host configuration
    os.symlink('/dev/null', os.path.join(systemd_system, 'tacacs-config.timer'))  # After boot Host configuration
    # Started by featured
    os.symlink('/lib/systemd/system/lldp.service', os.path.join(sonic_target_wants, 'lldp.service'))
    os.symlink('/lib/systemd/system/pmon.service', os.path.join(systemd_system, 'pmon.service'))
    os.symlink('/lib/systemd/system/pmon.service', os.path.join(sonic_target_wants, 'pmon.service'))

    # Workaround: Only useful for BackEndToRRouter
    os.symlink('/dev/null', os.path.join(systemd_system, 'backend-acl.service'))

    # Workaround: We don't need LACP
    os.symlink('/dev/null', os.path.join(systemd_system, 'teamd.service'))

    # Workaround: Python module sonic_platform not present on vs images
    os.symlink('/dev/null', os.path.join(systemd_system, 'system-health.service'))
    os.symlink('/dev/null', os.path.join(systemd_system, 'watchdog-control.service'))

    etc_sonic = os.path.join(image, 'rw/etc/sonic/')
    os.makedirs(etc_sonic, exist_ok=True)

    sonic_version = image.removeprefix('/image-').removesuffix('/')
    sonic_environment = f'''
        SONIC_VERSION=${sonic_version}
        PLATFORM=x86_64-kvm_x86_64-r0
        HWSKU=Force10-S6000
        DEVICE_TYPE=LeafRouter
        ASIC_TYPE=vs
        '''.encode('utf-8')
    with open(os.path.join(etc_sonic, 'sonic-environment'), mode='wb') as file:
        file.write(sonic_environment)

    with open('/config_db.json') as f:
        config_db = json.load(f)

    config_db['DEVICE_METADATA']['localhost']['hostname'] = socket.gethostname()
    config_db['DEVICE_METADATA']['localhost']['mac'] = get_mac_address('eth0')
    cidr = get_ip_address('eth0') + '/16'
    config_db['MGMT_INTERFACE'] = {
        f'eth0|{cidr}': {
            'gwaddr': get_default_gateway()
        }
    }

    config_db_json = json.dumps(config_db, indent=4, sort_keys=True)
    with open(os.path.join(etc_sonic, 'config_db.json'), mode='wb') as file:
        file.write(config_db_json.encode('utf-8'))

    if os.path.exists('/authorized_keys'):
        os.makedirs(os.path.join(image, 'rw/root/.ssh'))
        os.chmod(os.path.join(image, 'rw/root/.ssh'), 0o600)
        shutil.copy('/authorized_keys', os.path.join(image, 'rw/root/.ssh/'))
        os.chown(os.path.join(image, 'rw/root/.ssh/authorized_keys'), 0, 0)


def main():
    signal.signal(signal.SIGINT, handle_exit)
    signal.signal(signal.SIGTERM, handle_exit)

    logging.basicConfig(level=logging.INFO, stream=sys.stdout)
    logger = logging.getLogger()

    name = os.getenv('CLAB_LABEL_CLAB_NODE_NAME', default='switch')
    smp = os.getenv('QEMU_SMP', default='2')
    memory = os.getenv('QEMU_MEMORY', default='2048')
    interfaces = int(os.getenv('CLAB_INTFS', 0)) + 1

    vm = Qemu(name, smp, memory, interfaces)

    logger.info('Prepare disk')
    vm.prepare_overlay(BASE_IMG)

    logger.info('Deploy initial config')
    path = '/media'
    vm.mount(path)
    initial_configuration(path)
    vm.umount(path)

    logger.info(f'Waiting for {interfaces} interfaces to be connected')
    wait_until_all_interfaces_are_connected(interfaces)

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
            if iface.startswith('eth'):
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


if __name__ == '__main__':
    main()
