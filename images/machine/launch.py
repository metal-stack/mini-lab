#!/usr/bin/python3
import logging
import os
import signal
import subprocess
import sys
import uuid


class Qemu:
    def __init__(self, name: str, uuid: str, cores: str, memory: str, interfaces: int, disk: str):
        self._name = name
        self._uuid = uuid
        self._cores = cores
        self._memory = memory
        self._interfaces = interfaces
        self._p = None
        self._disk = disk

    def start(self) -> None:
        cmd = [
            'qemu-system-x86_64',
            '-name', self._name,
            '-uuid', self._uuid,
            '-cpu', 'host',
            '-smp', 'cores=' + self._cores,
            '-m', self._memory,
            '-display', 'none',
            '-enable-kvm',
            '-machine', 'q35',
            '-nodefaults',
            '-drive', 'if=pflash,format=raw,readonly=on,file=/opt/OVMF/OVMF_CODE.fd',
            '-drive', 'if=pflash,format=raw,file=/opt/OVMF/OVMF_VARS.fd',
            '-drive', f"id=disk,if=none,format=qcow2,file={self._disk}",
            '-device', f"virtio-blk-pci,drive=disk,bootindex={self._interfaces}",
            '-chardev', 'socket,id=ipmi0,host=127.0.0.1,port=9000,reconnect=10',
            '-device', 'ipmi-bmc-extern,id=bmc0,chardev=ipmi0',
            '-device', 'pci-ipmi-kcs,bmc=bmc0',
            '-serial', 'telnet:127.0.0.1:9001,server,nowait',
        ]

        for i in range(self._interfaces):  # ignore eth0
            with open(f"/sys/class/net/lan{i}/address", 'r') as f:
                mac = f.read().strip()
            cmd.append('-device')
            cmd.append(f"virtio-net-pci,netdev=hn{i},mac={mac},romfile=,bootindex={i}")
            cmd.append('-netdev')
            cmd.append(f"tap,id=hn{i},ifname=tap{i},script=/mirror_tap_to_lan.sh,downscript=/remove_mirror.sh")

        self._p = subprocess.Popen(cmd)

    def wait(self) -> None:
        self._p.wait()


def main():
    signal.signal(signal.SIGINT, handle_exit)
    signal.signal(signal.SIGTERM, handle_exit)

    logging.basicConfig(level=logging.INFO, stream=sys.stdout)
    logger = logging.getLogger()

    name = os.getenv('CLAB_LABEL_CLAB_NODE_NAME', default='machine')
    cores = os.getenv('QEMU_CPU_CORES', default='1')
    memory = os.getenv('QEMU_MEMORY', default='2048')
    interfaces = int(os.getenv('CLAB_INTFS', 0))
    machine_uuid = os.getenv('UUID', str(uuid.uuid4()))

    vm = Qemu(name, machine_uuid, cores, memory, interfaces, '/disk.img')

    logger.info('Start QEMU')
    vm.start()

    logger.info('Wait until QEMU is terminated')
    vm.wait()


def handle_exit(signal, frame):
    sys.exit(0)


if __name__ == '__main__':
    main()
