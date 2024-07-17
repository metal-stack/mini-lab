.DEFAULT_GOAL := up
.EXPORT_ALL_VARIABLES:

# Commands
YQ=docker run --rm -i -v $(shell pwd):/workdir mikefarah/yq:4

KINDCONFIG := $(or $(KINDCONFIG),control-plane/kind.yaml)
KUBECONFIG := $(shell pwd)/.kubeconfig

MKE2FS_CONFIG := $(shell pwd)/mke2fs.conf
# Default values
CONTAINERLAB=$(shell which containerlab)

# extra vars can be used by projects that built on the mini-lab, which want to override default configuration
ANSIBLE_EXTRA_VARS_FILE := $(or $(ANSIBLE_EXTRA_VARS_FILE),)

MINI_LAB_FLAVOR := $(or $(MINI_LAB_FLAVOR),sonic)
MINI_LAB_VM_IMAGE := $(or $(MINI_LAB_VM_IMAGE),ghcr.io/metal-stack/mini-lab-vms:latest)
MINI_LAB_SONIC_IMAGE := $(or $(MINI_LAB_SONIC_IMAGE),ghcr.io/metal-stack/mini-lab-sonic:latest)

MACHINE_OS=ubuntu-24.04

# Machine flavors
ifeq ($(MINI_LAB_FLAVOR),cumulus)
LAB_MACHINES=machine01,machine02
LAB_TOPOLOGY=mini-lab.cumulus.yaml
else ifeq ($(MINI_LAB_FLAVOR),sonic)
LAB_MACHINES=machine01,machine02
LAB_TOPOLOGY=mini-lab.sonic.yaml
else ifeq ($(MINI_LAB_FLAVOR),mixed)
LAB_MACHINES=machine01,machine02
LAB_TOPOLOGY=mini-lab.mixed.yaml
else
$(error Unknown flavor $(MINI_LAB_FLAVOR))
endif

KIND_ARGS=
ifneq ($(K8S_VERSION),)
KIND_ARGS=--image kindest/node:v$(K8S_VERSION)
endif

ifeq ($(CI),true)
  DOCKER_COMPOSE_TTY_ARG=-T
else
  DOCKER_COMPOSE_TTY_ARG=
endif

.PHONY: up
up: env control-plane-bake partition-bake
	@chmod 600 files/ssh/id_rsa
	docker compose up --remove-orphans --force-recreate control-plane partition
	@$(MAKE)	--no-print-directory	start-machines
# for some reason an allocated machine will not be able to phone home
# without restarting the metal-core
# TODO: should be investigated and fixed if possible
	sleep 10
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o "PubkeyAcceptedKeyTypes +ssh-rsa" root@leaf01 -i files/ssh/id_rsa 'systemctl restart metal-core'
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o "PubkeyAcceptedKeyTypes +ssh-rsa" root@leaf02 -i files/ssh/id_rsa 'systemctl restart metal-core'

.PHONY: restart
restart: down up

.PHONY: down
down: cleanup

.PHONY: control-plane
control-plane: control-plane-bake env
	docker compose up --remove-orphans --force-recreate control-plane

.PHONY: control-plane-bake
control-plane-bake:
	@if ! which kind > /dev/null; then echo "kind needs to be installed"; exit 1; fi
	@if ! kind get clusters | grep metal-control-plane > /dev/null; then \
		kind create cluster $(KIND_ARGS) \
			--name metal-control-plane \
			--config $(KINDCONFIG) \
			--kubeconfig $(KUBECONFIG); fi

.PHONY: partition
partition: partition-bake
	docker compose up --remove-orphans --force-recreate partition

.PHONY: partition-bake
partition-bake:
	docker pull $(MINI_LAB_VM_IMAGE)
ifeq ($(MINI_LAB_FLAVOR),sonic)
	docker pull $(MINI_LAB_SONIC_IMAGE)
endif
	@if ! sudo $(CONTAINERLAB) --topo $(LAB_TOPOLOGY) inspect | grep -i leaf01 > /dev/null; then \
		sudo --preserve-env $(CONTAINERLAB) deploy --topo $(LAB_TOPOLOGY) --reconfigure && \
		./scripts/deactivate_offloading.sh; fi

.PHONY: env
env:
	@./env.sh

.PHONY: _ips
_ips:
	$(eval ipL1 = $(shell ${YQ} --unwrapScalar=true '.nodes.leaf01."mgmt-ipv4-address"' clab-mini-lab/topology-data.json))
	$(eval ipL2 = $(shell ${YQ} --unwrapScalar=true '.nodes.leaf02."mgmt-ipv4-address"' clab-mini-lab/topology-data.json))
	$(eval staticR = "100.255.254.0/24 nexthop via $(ipL1) dev docker0 nexthop via $(ipL2) dev docker0")

.PHONY: route
route: _ips
	eval "sudo ip r a ${staticR}"

.PHONY: cleanup
cleanup: cleanup-control-plane cleanup-partition

.PHONY: cleanup-control-plane
cleanup-control-plane:
	kind delete cluster --name metal-control-plane
	docker compose down
	rm -f $(KUBECONFIG)

.PHONY: cleanup-partition
cleanup-partition:
	sudo $(CONTAINERLAB) destroy --topo mini-lab.cumulus.yaml
	sudo $(CONTAINERLAB) destroy --topo mini-lab.sonic.yaml
	sudo $(CONTAINERLAB) destroy --topo mini-lab.mixed.yaml

.PHONY: _privatenet
_privatenet: env
	docker compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl network list --name user-private-network | grep user-private-network || docker compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl network allocate --partition mini-lab --project 00000000-0000-0000-0000-000000000000 --name user-private-network

.PHONY: machine
machine: _privatenet
	docker compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl machine create --description test --name test --hostname test --project 00000000-0000-0000-0000-000000000000 --partition mini-lab --image $(MACHINE_OS) --size v1-small-x86 --networks $(shell docker compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl network list --name user-private-network -o template --template '{{ .id }}')

.PHONY: firewall
firewall: _ips _privatenet
	docker compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl firewall create --description fw --name fw --hostname fw --project 00000000-0000-0000-0000-000000000000 --partition mini-lab --image firewall-ubuntu-3.0 --size v1-small-x86 --networks internet-mini-lab,$(shell docker compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl network list --name user-private-network -o template --template '{{ .id }}')

.PHONY: ls
ls: env
	docker compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl machine ls

## SWITCH MANAGEMENT ##

.PHONY: ssh-leafconfig
ssh-leafconfig:
	@grep "Host leaf01" ~/.ssh/config || echo -e "Host leaf01\n    StrictHostKeyChecking no\n    IdentityFile $(shell pwd)/files/ssh/id_rsa\n" >>~/.ssh/config
	@grep "Host leaf02" ~/.ssh/config || echo -e "Host leaf02\n    StrictHostKeyChecking no\n    IdentityFile $(shell pwd)/files/ssh/id_rsa\n" >>~/.ssh/config

.PHONY: docker-leaf01
docker-leaf01:
	@echo "export DOCKER_HOST=ssh://root@leaf01/var/run/docker.sock"

.PHONY: docker-leaf02
docker-leaf02:
	@echo "export DOCKER_HOST=ssh://root@leaf02/var/run/docker.sock"

.PHONY: ssh-leaf01
ssh-leaf01:
	ssh -o StrictHostKeyChecking=no -o "PubkeyAcceptedKeyTypes +ssh-rsa" -i files/ssh/id_rsa root@leaf01

.PHONY: ssh-leaf02
ssh-leaf02:
	ssh -o StrictHostKeyChecking=no -o "PubkeyAcceptedKeyTypes +ssh-rsa" -i files/ssh/id_rsa root@leaf02

## MACHINE MANAGEMENT ##

.PHONY: start-machines
start-machines:
	docker exec vms /mini-lab/manage_vms.py --names $(LAB_MACHINES) create

.PHONY: _password
_password: env
	docker compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl machine consolepassword $(MACHINE_UUID)

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
	docker compose run $(DOCKER_COMPOSE_TTY_ARG) metalctl machine rm $(MACHINE_UUID)
	docker exec vms /mini-lab/manage_vms.py --names $(MACHINE_NAME) kill --with-disks
	docker exec vms /mini-lab/manage_vms.py --names $(MACHINE_NAME) create

.PHONY: free-machine01
free-machine01:
	@$(MAKE) --no-print-directory _free-machine	MACHINE_NAME=machine01 MACHINE_UUID=e0ab02d2-27cd-5a5e-8efc-080ba80cf258

.PHONY: free-machine02
free-machine02:
	@$(MAKE) --no-print-directory _free-machine	MACHINE_NAME=machine02 MACHINE_UUID=2294c949-88f6-5390-8154-fa53d93a3313

.PHONY: free-machine03
free-machine03:
	@$(MAKE) --no-print-directory _free-machine	MACHINE_NAME=machine03 MACHINE_UUID=2a92f14d-d3b1-4d46-b813-5d058103743e

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
	@echo "export METALCTL_API_URL=http://api.172.17.0.1.nip.io:8080/metal"
	@echo "export METALCTL_HMAC=metal-admin"
	@echo "export KUBECONFIG=$(KUBECONFIG)"
