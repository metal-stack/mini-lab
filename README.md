# mini-lab

Small lab to setup the `metal-stack` locally. Starts two leaf switches and the [metal-api](https://github.com/metal-stack/metal-api) to try [metalctl](https://github.com/metal-stack/metalctl) and the creation of machines.

<!-- TOC depthFrom:2 depthTo:6 withLinks:1 updateOnSave:1 orderedList:0 -->

- [Requirements](#requirements)
- [Known Limitations](#known-limitations)
- [Try it out](#try-it-out)
	- [Reinstall machine](#reinstall-machine)
	- [Remove machine](#remove-machine)
- [Development of metal-api, metal-hammer and metal-core](#development-of-metal-api-metal-hammer-and-metal-core)

<!-- /TOC -->

## Requirements

- Linux
- Vagrant == 2.2.9 with vagrant-libvirt plugin >= 0.1.2 (for running the switch and machine VMs)
- docker >= 18.09 (for using our deployment base image)
- docker-compose >= 1.25.4 (for ease-of-use and parallelizing control plane and partition deployment)
- kvm as hypervisor for the VMs
- [ovmf](https://wiki.ubuntu.com/UEFI/OVMF) to have a uefi firmware for virtual machines
- [kind](https://github.com/kubernetes-sigs/kind/releases) == v0.8.1 (for hosting the metal control plane on a kubernetes cluster v1.18.2)
- the lab creates a virtual network 192.168.121.0/24 on your host machine, this hopefully does not overlap with other networks you have
- (optional) haveged to have enough random entropy - only needed if the PXE process does not work

Here is some code that should help you setting up most of the requirements:

 ```bash
# Install vagrant
wget https://releases.hashicorp.com/vagrant/2.2.9/vagrant_2.2.9_x86_64.deb
apt-get install ./vagrant_2.2.9_x86_64.deb docker.io qemu-kvm virt-manager ovmf net-tools libvirt-dev

# Ensure that your user is member of the group "libvirt"
usermod -G libvirt -a ${USER}

# Install libvirt plugin for vagrant
vagrant plugin install vagrant-libvirt

# Install kind from https://github.com/kubernetes-sigs/kind/releases
```

The following ports are getting used:

| Port | Bind Address  | Description                        |
|:----:|:-------------:|:---------------------------------- |
| 8443 | 0.0.0.0       | kube-apiserver of the kind cluster |
| 4443 | 192.168.121.1 | HTTPS ingress                      |
| 4150 | 192.168.121.1 | nsqd                               |
| 4161 | 192.168.121.1 | nsq-lookupd                        |
| 5222 | 192.168.121.1 | metal-console                      |
| 8080 | 192.168.121.1 | HTTP ingress                       |

## Known Limitations

- to keep the demo small there is no EVPN
- machine restart and destroy does not work because we cannot change the boot order via IPMI in the lab easily (virtual-bmc could, but it's buggy)
- login to the machines is only possible with virsh console

## Try it out

Start the mini-lab with a kind cluster, a metal-api instance as well as some vagrant VMs with two leaf switches and two machine skeletons.

```bash
make
```

Two machines in status `PXE booting` are visible with `metalctl machine ls`

```bash
docker-compose run metalctl machine ls

ID                                          LAST EVENT   WHEN     AGE  HOSTNAME  PROJECT  SIZE          IMAGE  PARTITION
e0ab02d2-27cd-5a5e-8efc-080ba80cf258        PXE Booting  3s
2294c949-88f6-5390-8154-fa53d93a3313        PXE Booting  5s
```

Wait until the machines reach the waiting state

```bash
docker-compose run metalctl machine ls

ID                                          LAST EVENT   WHEN     AGE  HOSTNAME  PROJECT  SIZE          IMAGE  PARTITION
e0ab02d2-27cd-5a5e-8efc-080ba80cf258        Waiting      8s                               v1-small-x86         vagrant
2294c949-88f6-5390-8154-fa53d93a3313        Waiting      8s                               v1-small-x86         vagrant
```

Create a machine with

```bash
make machine
```

or the hard way with

```bash
docker-compose run metalctl network allocate \
        --partition vagrant \
        --project 00000000-0000-0000-0000-000000000000 \
        --name vagrant
```

Lookup the network ID and run

```bash
docker-compose run metalctl machine create \
        --description test \
        --name machine \
        --hostname machine \
        --project 00000000-0000-0000-0000-000000000000 \
        --partition vagrant \
        --image ubuntu-19.10 \
        --size v1-small-x86 \
        --networks <network-ID>
```

See the installation process in action

```bash
virsh console metal_machine01/02
...
Ubuntu 19.10 machine ttyS0

machine login:
```

One machine is now installed and has status "Phoned Home"

```bash
docker-compose run metalctl machine ls
ID                                          LAST EVENT   WHEN   AGE     HOSTNAME  PROJECT                               SIZE          IMAGE         PARTITION
e0ab02d2-27cd-5a5e-8efc-080ba80cf258        Phoned Home  2s     21s     machine   00000000-0000-0000-0000-000000000000  v1-small-x86  Ubuntu 19.10  vagrant
2294c949-88f6-5390-8154-fa53d93a3313        Waiting      8s                                                             v1-small-x86                vagrant
```

Login with user name metal and the console password from

```bash
docker-compose run metalctl machine describe e0ab02d2-27cd-5a5e-8efc-080ba80cf258 | grep password

consolepassword: ...
```

To remove the kind cluster and the vagrant boxes, run

```bash
make cleanup
```

### Reinstall machine

Reinstall a machine with

```bash
docker-compose run metalctl machine reinstall \
        --image ubuntu-19.10 \
        e0ab02d2-27cd-5a5e-8efc-080ba80cf258
```

### Remove machine

Remove a machine with

```bash
docker-compose run metalctl machine rm e0ab02d2-27cd-5a5e-8efc-080ba80cf258
```

## Development of metal-api, metal-hammer and metal-core

To simplify developing changes for the `metal-api`, `metal-hammer` and `metal-core`, it is possible to use development artifacts from within the mini-lab.
See the [dev instructions](DEV_INSTRUCTIONS.md) for more details.
