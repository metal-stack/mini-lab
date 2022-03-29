.DEFAULT_GOAL := up
.EXPORT_ALL_VARIABLES:

# Commands
YQ=docker run --rm -i -v $(shell pwd):/workdir mikefarah/yq:3 /bin/sh -c

KUBECONFIG := $(shell pwd)/.kubeconfig

# Default values
DOCKER_COMPOSE_OVERRIDE=

MINI_LAB_FLAVOR := $(or $(MINI_LAB_FLAVOR),default)
MINI_LAB_VM_IMAGE := $(or $(MINI_LAB_VM_IMAGE),ghcr.io/metal-stack/mini-lab-vms:latest)

MACHINE_OS=ubuntu-20.04

# Machine flavors
ifeq ($(MINI_LAB_FLAVOR),default)
LAB_MACHINES=machine01,machine02
else ifeq ($(MINI_LAB_FLAVOR),cluster-api)
LAB_MACHINES=machine01,machine02,machine03
else
$(error Unknown flavor $(MINI_LAB_FLAVOR))
endif

ifeq ($(CI),true)
  DOCKER_COMPOSE_TTY_ARG=-T
else
  DOCKER_COMPOSE_TTY_ARG=
endif

.PHONY: up
up: env control-plane-bake partition-bake
	@chmod 600 files/ssh/id_rsa
	docker-compose up --remove-orphans --force-recreate control-plane partition
	@$(MAKE)	--no-print-directory	start-machines
# for some reason an allocated machine will not be able to phone home
# without restarting the metal-core
# TODO: should be investigated and fixed if possible
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@leaf01 -i files/ssh/id_rsa 'systemctl restart metal-core'
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@leaf02 -i files/ssh/id_rsa 'systemctl restart metal-core'

.PHONY: restart
restart: down up

.PHONY: down
down: cleanup

.PHONY: control-plane
control-plane: control-plane-bake env
	docker-compose up --remove-orphans --force-recreate control-plane

.PHONY: control-plane-bake
control-plane-bake:
	@if ! which kind > /dev/null; then echo "kind needs to be installed"; exit 1; fi
	@if ! kind get clusters | grep metal-control-plane > /dev/null; then \
		kind create cluster \
		  --name metal-control-plane \
			--config control-plane/kind.yaml \
			--kubeconfig $(KUBECONFIG); fi

.PHONY: partition
partition: partition-bake
	docker-compose -f docker-compose.yml $(DOCKER_COMPOSE_OVERRIDE) up --remove-orphans --force-recreate partition

.PHONY: partition-bake
partition-bake:
	# docker pull $(MINI_LAB_VM_IMAGE)
	@if ! sudo containerlab --topo mini-lab.clab.yaml inspect | grep -i running > /dev/null; then \
		sudo --preserve-env containerlab deploy --topo mini-lab.clab.yaml --reconfigure && \
		./scripts/deactivate_offloading.sh; fi

.PHONY: env
env:
	@./env.sh

.PHONY: _ips
_ips:
	$(eval ipL1 = $(shell ${YQ} "yq r clab-mini-lab/ansible-inventory.yml 'all.children.cvx.hosts.leaf01.ansible_host'"))
	$(eval ipL2 = $(shell ${YQ} "yq r clab-mini-lab/ansible-inventory.yml 'all.children.cvx.hosts.leaf02.ansible_host'"))
	$(eval staticR = "100.255.254.0/24 nexthop via $(ipL1) dev docker0 nexthop via $(ipL2) dev docker0")

.PHONY: route
route: _ips
	eval "sudo ip r a ${staticR}"

# there is no libvirt required anymore and thus following rules will not work on systems without
# TODO: discuss what to do instead?
.PHONY: fwrules
fwrules: _ips
	eval "sudo -- iptables -I LIBVIRT_FWO -s 100.255.254.0/24 -i docker0 -j ACCEPT;"
	eval "sudo -- iptables -I LIBVIRT_FWO -s 10.0.1.0/24 -i docker0 -j ACCEPT;"
	eval "sudo -- iptables -I LIBVIRT_FWI -d 100.255.254.0/24 -o docker0 -j ACCEPT;"
	eval "sudo -- iptables -I LIBVIRT_FWI -d 10.0.1.0/24 -o docker0 -j ACCEPT;"
	eval "sudo -- iptables -t nat -I LIBVIRT_PRT -s 100.255.254.0/24 ! -d 100.255.254.0/24 -j MASQUERADE"
	eval "sudo -- iptables -t nat -I LIBVIRT_PRT -s 10.0.1.0/24 ! -d 10.0.1.0/24 -j MASQUERADE"

.PHONY: cleanup
cleanup: cleanup-control-plane cleanup-partition

.PHONY: cleanup-control-plane
cleanup-control-plane:
	kind delete cluster --name metal-control-plane
	docker-compose down
	rm -f $(KUBECONFIG)

.PHONY: cleanup-partition
cleanup-partition:
	sudo containerlab destroy --topo mini-lab.clab.yaml

.PHONY: _privatenet
_privatenet: env
	docker-compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl network list --name user-private-network | grep user-private-network || docker-compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl network allocate --partition mini-lab --project 00000000-0000-0000-0000-000000000000 --name user-private-network

.PHONY: machine
machine: _privatenet
	docker-compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl machine create --description test --name test --hostname test --project 00000000-0000-0000-0000-000000000000 --partition mini-lab --image $(MACHINE_OS) --size v1-small-x86 --networks $(shell docker-compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl network list --name user-private-network -o template --template '{{ .id }}')

.PHONY: firewall
firewall: _ips _privatenet
	docker-compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl firewall create --description fw --name fw --hostname fw --project 00000000-0000-0000-0000-000000000000 --partition mini-lab --image firewall-ubuntu-2.0 --size v1-small-x86 --networks internet-mini-lab,$(shell docker-compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl network list --name user-private-network -o template --template '{{ .id }}')

.PHONY: ls
ls: env
	docker-compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl machine ls

## SWITCH MANAGEMENT ##

.PHONY: ssh-leaf01
ssh-leaf01:
	ssh -o StrictHostKeyChecking=no -i files/ssh/id_rsa root@leaf01

.PHONY: ssh-leaf02
ssh-leaf02:
	ssh -o StrictHostKeyChecking=no -i files/ssh/id_rsa root@leaf02

## MACHINE MANAGEMENT ##

.PHONY: start-machines
start-machines:
	docker exec vms /mini-lab/manage_vms.py --names $(LAB_MACHINES) create

.PHONY: _reboot-machine
_reboot-machine:
	docker exec vms /mini-lab/manage_vms.py --names $(MACHINE_NAME) kill
	docker exec vms /mini-lab/manage_vms.py --names $(MACHINE_NAME) create

.PHONY: reboot-machine01
reboot-machine01:
	@$(MAKE)	--no-print-directory	_reboot-machine	MACHINE_NAME=machine01

.PHONY: reboot-machine02
reboot-machine02:
	@$(MAKE)	--no-print-directory	_reboot-machine	MACHINE_NAME=machine02

.PHONY: reboot-machine03
reboot-machine03:
	@$(MAKE)	--no-print-directory	_reboot-machine	MACHINE_NAME=machine03

.PHONY: _password
_password: env
	docker-compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl machine consolepassword $(MACHINE_UUID)

.PHONY: password-machine01
password-machine01:
	@$(MAKE)	--no-print-directory	_password	MACHINE_UUID=e0ab02d2-27cd-5a5e-8efc-080ba80cf258

.PHONY: password-machine02
password-machine02:
	@$(MAKE)	--no-print-directory	_password	MACHINE_UUID=2294c949-88f6-5390-8154-fa53d93a3313

.PHONY: password-machine03
password-machine03:
	@$(MAKE)	--no-print-directory	_password	MACHINE_UUID=2a92f14d-d3b1-4d46-b813-5d058103743e

.PHONY: _free-machine
_free-machine: env
	docker-compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl machine rm $(MACHINE_UUID)
	@$(MAKE) --no-print-directory reboot-machine	MACHINE_NAME=$(MACHINE_NAME)

.PHONY: free-machine01
free-machine01:
	@$(MAKE) --no-print-directory _free-machine	MACHINE_NAME=machine01

.PHONY: free-machine02
free-machine02:
	@$(MAKE) --no-print-directory _free-machine	MACHINE_NAME=machine02

.PHONY: free-machine03
free-machine03:
	@$(MAKE) --no-print-directory _free-machine	MACHINE_NAME=machine03

.PHONY: _console-machine
_console-machine:
	@echo "exit console with CTRL+5 and then quit telnet through q + ENTER"
	@docker exec -it vms telnet 127.0.0.1 $(CONSOLE_PORT)

.PHONY: console-machine01
console-machine01:
	@$(MAKE) --no-print-directory _console-machine	CONSOLE_PORT=4000

.PHONY: console-machine02
console-machine02:
	@$(MAKE) --no-print-directory _console-machine	CONSOLE_PORT=4001

.PHONY: console-machine03
console-machine03:
	@$(MAKE) --no-print-directory _console-machine	CONSOLE_PORT=4002

## DEV TARGETS ##

.PHONY: dev-env
dev-env:
	@echo "export METALCTL_URL=http://api.0.0.0.0.nip.io:8080/metal"
	@echo "export METALCTL_HMAC=metal-admin"
	@echo "export KUBECONFIG=$(KUBECONFIG)"

.PHONY: build-vms-image
build-vms-image:
	cd images && docker build -f Dockerfile.vms -t $(MINI_LAB_VM_IMAGE) . && cd -
