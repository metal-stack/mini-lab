#!/usr/bin/python3
import fcntl
import logging
import os
import signal
import socket
import struct
import subprocess
import sys
import telnetlib
import time

BASE_IMG = '/sonic-vs.img'
USER = 'admin'
PASSWORD = 'YourPaSsWoRd'


class Qemu:
    def __init__(self, name: str, memory: str, interfaces: int):
        self._name = name
        self._memory = memory
        self._interfaces = interfaces
        self._p = None
        self._disk = '/overlay.img'

    def prepare_overlay(self, base: str) -> None:
        cmd = [
            'qemu-img',
            'create',
            '-f', 'qcow2',
            '-b', base,
            self._disk,
        ]
        subprocess.run(cmd, check=True)

    def start(self) -> None:
        cmd = [
            'qemu-system-x86_64',
            '-cpu', 'host',
            '-display', 'none',
            '-enable-kvm',
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
            cmd.append(f'virtio-net,netdev=hn{i},mac={mac}')
            cmd.append(f'-netdev')
            cmd.append(f'tap,id=hn{i},ifname=tap{i},script=/mini-lab/mirror_tap_to_eth.sh,downscript=no')

        self._p = subprocess.Popen(cmd)

    def wait(self) -> None:
        self._p.wait()


class Telnet:
    def __init__(self):
        self._tn: telnetlib.Telnet | None = None

    def connect(self, host: str, port: int, max_retries=60) -> bool:
        for i in range(1, max_retries + 1):
            try:
                self._tn = telnetlib.Telnet(host, port)
                return True
            except:
                time.sleep(1)
            if i == max_retries:
                return False

    def close(self):
        self._tn.close()

    def wait_until(self, match: str):
        self._tn.read_until(match.encode('ascii'))

    def write_and_wait(self, data: str, match: str = '$ ') -> str:
        self._tn.write(data.encode('ascii') + b'\n')
        return self._tn.read_until(match.encode('ascii')).decode('utf-8')

    def write_test(self, data: str) -> str:
        self._tn.write(data.encode('ascii') + b'\n')
        time.sleep(5)
        return self._tn.read_some().decode('utf-8')


def main():
    signal.signal(signal.SIGINT, handle_exit)
    signal.signal(signal.SIGTERM, handle_exit)

    logging.basicConfig(level=logging.INFO, stream=sys.stdout)
    logger = logging.getLogger()

    name = os.getenv('CLAB_LABEL_CLAB_NODE_NAME', default='switch')
    memory = os.getenv('VM_MEMORY', default='2048')
    interfaces = int(os.getenv('CLAB_INTFS', 0)) + 1

    logger.info(f'Waiting for {interfaces} interfaces to be connected')
    wait_until_all_interfaces_are_connected(interfaces)

    vm = Qemu(name, memory, interfaces)

    logger.info('Prepare disk')
    vm.prepare_overlay(BASE_IMG)

    logger.info('Start QEMU')
    vm.start()

    logger.info('Try to connect via telnet...')
    tn = Telnet()
    if not tn.connect('127.0.0.1', 5000):
        logger.error('Cannot connect to telnet server')
        sys.exit(1)

    logger.info('Connected via telnet and waiting for login prompt')
    tn.wait_until('login: ')

    logger.info('Try to login')
    tn.write_and_wait(USER, 'Password: ')
    tn.write_and_wait(PASSWORD)

    logger.info('Authorize ssh key')
    authorize_ssh_key(tn)

    logger.info('Wait until config-setup is done')
    if not wait_until_config_setup_is_done(tn):
        logger.error('config-setup still not done')
        sys.exit(1)

    net = get_ip_address('eth0') + '/16'
    logger.info(f'Configure {net} on eth0')
    tn.write_and_wait(f'sudo config interface ip add eth0 {net}')
    tn.write_and_wait('sudo config save --yes')

    tn.close()

    logger.info('Wait until QEMU terminated')
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


def wait_until_config_setup_is_done(tn: Telnet, max_retries: int = 60) -> bool:
    for i in range(1, max_retries + 1):
        # updategraph is started after the config-setup
        result = tn.write_and_wait('systemctl is-active updategraph')
        if not 'inactive' in result:
            return True
        time.sleep(1)
        if i == max_retries:
            return False


def authorize_ssh_key(tn: Telnet) -> None:
    with open('/id_rsa.pub') as f:
        key = f.read().strip()

    tn.write_and_wait(f'echo "{key}" > authorized_keys')
    tn.write_and_wait('sudo mkdir /root/.ssh')
    tn.write_and_wait('sudo chmod 0600 /root/.ssh')
    tn.write_and_wait('sudo cp authorized_keys /root/.ssh/')


if __name__ == '__main__':
    main()
