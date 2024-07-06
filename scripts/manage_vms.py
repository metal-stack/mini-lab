#!/usr/bin/env python3

import argparse
import os
import signal
import subprocess
import sys

VMS = {
    "machine01": {
        "name": "machine01",
        "uuid": "e0ab02d2-27cd-5a5e-8efc-080ba80cf258",
        "disk-path": "/machine01.img",
        "disk-size": "5G",
        "memory": "2G",
        "lan_indices": [0, 1],
        "serial-port": 4000,
    },
    "machine02": {
        "name": "machine02",
        "uuid": "2294c949-88f6-5390-8154-fa53d93a3313",
        "disk-path": "/machine02.img",
        "disk-size": "5G",
        "memory": "2G",
        "lan_indices": [2, 3],
        "serial-port": 4001,
    },
    "machine03": {
        "name": "machine03",
        "uuid": "2a92f14d-d3b1-4d46-b813-5d058103743e",
        "disk-path": "/machine03.img",
        "disk-size": "5G",
        "memory": "2G",
        "lan_indices": [4, 5],
        "serial-port": 4002,
    },
}


def parse_args():
    parser = argparse.ArgumentParser(description="manages vms in the mini-lab")
    parser.add_argument("--names", type=str, help="the machine names to manage", required=True)

    subparsers = parser.add_subparsers(help='sub-command help')

    create = subparsers.add_parser('create', help='creates vms')
    create.set_defaults(entry_function="create")

    kill = subparsers.add_parser('kill', help='kills vm processes')
    kill.set_defaults(entry_function="kill")
    kill.add_argument("--with-disks", default=False, action='store_true', help="also deletes the vm's disks")

    return parser.parse_args()


class Manager:
    def __init__(self, args):
        self.subcommand = args.entry_function if 'entry_function' in args else None
        self.names = []
        if args.names:
            self.names = args.names.split(",")
        self.with_disks = args.with_disks if 'with_disks' in args else False

    def run(self):
        subcommands = {
            "create": self._create,
            "kill": self._kill,
        }

        command = subcommands.get(self.subcommand)
        if not command:
            sys.exit("requires valid subcommand: {commands}".format(
                commands=list(subcommands.keys())))

        command()


    def _machines_from_cmdline(self):
        machines = []
        for name in self.names:
            if name not in VMS:
                sys.exit("machine not found: {name}".format(name=name))
            machines.append(VMS[name])
        return machines


    def _create(self):
        for machine in self._machines_from_cmdline():
            Manager._create_vm_disk(machine.get(
                "disk-path"), machine.get("disk-size"))
            Manager._start_vm(machine)


    def _kill(self):
        for machine in self._machines_from_cmdline():
            Manager._kill_vm_process(machine.get("uuid"))
            if self.with_disks:
                Manager._delete_vm_disk(machine.get("disk-path"))


    @staticmethod
    def _kill_vm_process(machine_uuid):
        for line in os.popen("ps ax | grep qemu-system | grep " + machine_uuid + " | grep -v grep"):
            fields = line.split()
            if len(fields) == 0:
                print("vm process not found")
                return

            pid = fields[0]
            os.kill(int(pid), signal.SIGKILL)


    @staticmethod
    def _create_vm_disk(path, size):
        if os.path.isfile(path):
            print("disk already exists")
            return
        subprocess.run(['qemu-img', 'create', '-f', 'qcow2', path, size])

    @staticmethod
    def _delete_vm_disk(path):
        if not os.path.isfile(path):
            print("disk does not exist")
            return
        os.remove(path)

    @staticmethod
    def _start_vm(machine):
        cmd = [
            "qemu-system-x86_64",
            "-name", machine.get("name"),
            "-uuid", machine.get("uuid"),
            "-m", machine.get("memory"),
            "-boot", "n",
            "-cpu", "host",
            "-drive", "if=virtio,format=qcow2,file={disk}".format(disk=machine.get("disk-path")),
            "-drive", "if=pflash,format=raw,readonly,file=/usr/share/OVMF/OVMF_CODE.fd",
            "-drive", "if=pflash,format=raw,readonly,file=/usr/share/OVMF/OVMF_VARS.fd",
            "-serial", "telnet:127.0.0.1:{port},server,nowait".format(port=machine.get("serial-port")),
            "-enable-kvm",
            "-nographic",
        ]

        for lan_index in machine["lan_indices"]:
            mac = subprocess.check_output(["cat", f"/sys/class/net/lan{lan_index}/address"]).decode("utf-8").strip()

            cmd.append(f"-device virtio-net,netdev=hn{lan_index},mac={mac}")
            cmd.append(f"-netdev tap,id=hn{lan_index},ifname=tap{lan_index},script=/mini-lab/mirror_tap_to_lan.sh,downscript=no")

        cmd.append("&")

        cmd = " ".join(cmd)
        print(cmd)

        subprocess.Popen(cmd, shell=True, executable="/bin/bash")

if __name__ == '__main__':
    args = parse_args()
    m = Manager(args)
    m.run()
