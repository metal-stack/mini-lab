#!/usr/bin/env python3

import argparse
import sys
import subprocess
import os

VMS = [
    {
        "name": "machine01",
        "uuid": "e0ab02d2-27cd-5a5e-8efc-080ba80cf258",
        "disk-path": "/machine01.img",
        "disk-size": "5G",
        "memory": "2G",
        "tap-index-fd": [(0, 3), (1, 4)],
        "serial-port": 4000,
    },
    {
        "name": "machine02",
        "uuid": "2294c949-88f6-5390-8154-fa53d93a3313",
        "disk-path": "/machine02.img",
        "disk-size": "5G",
        "memory": "2G",
        "tap-index-fd": [(2, 5), (3, 6)],
        "serial-port": 4001,
    },
    {
        "name": "machine03",
        "uuid": "2a92f14d-d3b1-4d46-b813-5d058103743e",
        "disk-path": "/machine03.img",
        "disk-size": "5G",
        "memory": "2G",
        "tap-index-fd": [(4, 7), (5, 8)],
        "serial-port": 4002,
    },
]


def parse_args():
    parser = argparse.ArgumentParser(description="manages vms in the mini-lab")
    subparsers = parser.add_subparsers(help='sub-command help')

    create = subparsers.add_parser('create', help='creates vms')
    create.set_defaults(entry_function="create")
    create.add_argument("-n", "--number", "--amount", type=int,
                        help="number of vms to spin up", default=2)
    create.add_argument("--uuid", type=str, help="a specific machine to create")

    return parser.parse_args()


class Manager:
    def __init__(self, args):
        self.subcommand = args.entry_function if 'entry_function' in args else None
        self.amount = args.number if 'number' in args else None
        self.uuid = args.uuid if 'uuid' in args else None

    def run(self):
        subcommands = {
            "create": self._create,
        }

        command = subcommands.get(self.subcommand)
        if not command:
            sys.exit("requires valid subcommand: {commands}".format(
                commands=list(subcommands.keys())))

        command()

    def _create(self):
        machines_to_create = []

        if self.uuid:
            for machine in VMS:
                if machine.get("uuid") == self.uuid:
                    machines_to_create.append(machine)
                    break
        else:
            for index, machine in enumerate(VMS):
                if index < self.amount:
                    machines_to_create.append(machine)
                else:
                    break

        for machine in machines_to_create:
            Manager._create_vm_disk(machine.get(
                "disk-path"), machine.get("disk-size"))
            Manager._start_vm(machine)

    @staticmethod
    def _create_vm_disk(path, size):
        if os.path.isfile(path):
            print("disk already exists")
            return
        subprocess.run(['qemu-img', 'create', '-f', 'qcow2', path, size])

    @staticmethod
    def _start_vm(machine):
        nics = []
        netdevices = []
        for tap in machine.get("tap-index-fd", []):
            mac = subprocess.check_output(["cat", "/sys/class/net/tap{ifindex}/address".format(ifindex=tap[0])]).decode("utf-8").strip()
            # ifindex = subprocess.check_output(["cat", "/sys/class/net/tap{ifindex}/ifindex".format(ifindex=tap[0])]).decode("utf-8").strip()

            nics.append("nic,model=virtio,netdev=net{ifindex},macaddr={mac}".format(ifindex=tap[0], mac=mac))
            netdevices.append("user,id=net{ifindex},ifname=tap{ifindex}@lan{ifindex}".format(ifindex=tap[0]))

        cmd = [
            "qemu-system-x86_64",
            "-name", machine.get("name"),
            "-uuid", machine.get("uuid"),
            "-m", machine.get("memory"),
            "-boot", "n",
            "-drive", "if=virtio,format=qcow2,file={disk}".format(disk=machine.get("disk-path")),
            "-drive", "if=pflash,format=raw,readonly,file=/usr/share/OVMF/OVMF_CODE.fd",
            "-drive", "if=pflash,format=raw,file=/usr/share/OVMF/OVMF_VARS.fd",
            "-serial", "telnet:127.0.0.1:{port},server,nowait".format(
                port=machine.get("serial-port")),
            "-enable-kvm",
            "-nographic",
        ]

        for device in netdevices:
            cmd.append("-netdev")
            cmd.append(device)

        for nic in nics:
            cmd.append("-net")
            cmd.append(nic)

        print(cmd)

        subprocess.Popen(cmd)

if __name__ == '__main__':
    args = parse_args()
    m = Manager(args)
    m.run()
