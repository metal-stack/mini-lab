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
MAX_RETRIES := 30

# Machine flavors
ifeq ($(MINI_LAB_FLAVOR),cumulus)
LAB_TOPOLOGY=mini-lab.cumulus.yaml
VRF=vrf20
else ifeq ($(MINI_LAB_FLAVOR),sonic)
LAB_TOPOLOGY=mini-lab.sonic.yaml
VRF=Vrf20
else
$(error Unknown flavor $(MINI_LAB_FLAVOR))
endif

KIND_ARGS=
ifneq ($(K8S_VERSION),)
KIND_ARGS=--image kindest/node:v$(K8S_VERSION)
endif

ifeq ($(CI),true)
  METALCTL=docker compose run --no-TTY metalctl
else
  METALCTL=docker compose run --rm metalctl
endif

.PHONY: up
up: env control-plane-bake partition-bake
	@chmod 600 files/ssh/id_rsa
	docker compose up --remove-orphans --force-recreate control-plane partition
	@$(MAKE) --no-print-directory start-vm01
	@$(MAKE) --no-print-directory start-vm02
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
partition-bake: external_network
	docker pull $(MINI_LAB_VM_IMAGE)
ifeq ($(MINI_LAB_FLAVOR),sonic)
	docker pull $(MINI_LAB_SONIC_IMAGE)
endif
	@if ! sudo $(CONTAINERLAB) --topo $(LAB_TOPOLOGY) inspect | grep -i leaf01 > /dev/null; then \
		sudo --preserve-env $(CONTAINERLAB) deploy --topo $(LAB_TOPOLOGY) --reconfigure && \
		./scripts/deactivate_offloading.sh; fi

.PHONY: external_network
external_network:
	@if ! docker network ls | grep -q mini_lab_ext; then \
  		docker network create mini_lab_ext \
			--driver=bridge \
			--gateway=203.0.113.1 \
			--subnet=203.0.113.0/24 \
			--opt "com.docker.network.driver.mtu=9000" \
			--opt "com.docker.network.bridge.name=mini_lab_ext" \
			--opt "com.docker.network.bridge.enable_ip_masquerade=true" && \
		sudo ip route add 203.0.113.128/25 via 203.0.113.2 dev mini_lab_ext; fi

.PHONY: env
env:
	@./env.sh

.PHONY: cleanup
cleanup: cleanup-control-plane cleanup-partition

.PHONY: cleanup-control-plane
cleanup-control-plane:
	kind delete cluster --name metal-control-plane
	docker compose down
	rm -f $(KUBECONFIG)

.PHONY: cleanup-partition
cleanup-partition:
	mkdir -p clab-mini-lab
	sudo --preserve-env $(CONTAINERLAB) destroy --topo mini-lab.cumulus.yaml
	sudo --preserve-env $(CONTAINERLAB) destroy --topo mini-lab.sonic.yaml
	docker network rm --force mini_lab_ext

.PHONY: _privatenet
_privatenet: env
	$(METALCTL) network list --name user-private-network | grep user-private-network || $(METALCTL) network allocate --partition mini-lab --project 00000000-0000-0000-0000-000000000001 --name user-private-network

define create_public_ip
	$(METALCTL) network ip list --name $(1) | grep $(1) || $(METALCTL) network ip create --network internet-mini-lab --project 00000000-0000-0000-0000-000000000001 --ipaddress $(2) --name $(1)
endef

define create_common_args
	--description $(1) --name $(1) --hostname $(1) --project 00000000-0000-0000-0000-000000000001 --partition mini-lab --size v1-small-x86 --userdata "@/tmp/ignition.json"
endef

.PHONY: firewall
firewall: _privatenet
	$(call create_public_ip,firewall,203.0.113.129)
	$(METALCTL) firewall create $(call create_common_args,firewall) --firewall-rules-file=/tmp/rules.yaml --image firewall-ubuntu-3.0 --ips 203.0.113.129 \
		--networks internet-mini-lab,$(shell $(METALCTL) network list --name user-private-network -o template --template '{{ .id }}')

.PHONY: machine01
machine01: _privatenet
	$(call create_public_ip,machine01,203.0.113.130)
	$(METALCTL) machine create $(call create_common_args,machine01) --image $(MACHINE_OS) --ips 203.0.113.130 \
		--networks internet-mini-lab,$(shell $(METALCTL) network list --name user-private-network -o template --template '{{ .id }}')

.PHONY: machine02
machine02: _privatenet
	$(call create_public_ip,machine02,203.0.113.131)
	$(METALCTL) machine create $(call create_common_args,machine02) --image $(MACHINE_OS) --ips 203.0.113.131 \
		--networks internet-mini-lab,$(shell $(METALCTL) network list --name user-private-network -o template --template '{{ .id }}')

.PHONY: ls
ls: env
	$(METALCTL) machine ls

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

## MACHINE VM MANAGEMENT ##

.PHONY: start-vm01
start-vm01:
	docker exec vms /mini-lab/manage_vms.py --names vm01 create

.PHONY: start-vm02
start-vm02:
	docker exec vms /mini-lab/manage_vms.py --names vm02 create

.PHONY: start-vm03
start-vm03:
	docker exec vms /mini-lab/manage_vms.py --names vm03 create

.PHONY: _password
_password: env
	$(METALCTL) machine consolepassword $(MACHINE_UUID)

.PHONY: password-vm01
password-vm01:
	@$(MAKE) --no-print-directory _password MACHINE_UUID=e0ab02d2-27cd-5a5e-8efc-080ba80cf258

.PHONY: password-vm02
password-vm02:
	@$(MAKE) --no-print-directory _password MACHINE_UUID=2294c949-88f6-5390-8154-fa53d93a3313

.PHONY: password-vm03
password-vm03:
	@$(MAKE) --no-print-directory _password MACHINE_UUID=2a92f14d-d3b1-4d46-b813-5d058103743e

.PHONY: _free_vm
_free_vm: env
	$(METALCTL) machine rm $(MACHINE_UUID)
	docker exec vms /mini-lab/manage_vms.py --names $(VM_NAME) kill --with-disks
	docker exec vms /mini-lab/manage_vms.py --names $(VM_NAME) create

.PHONY: free-vm01
free-vm01:
	@$(MAKE) --no-print-directory _free_vm VM_NAME=vm01 MACHINE_UUID=e0ab02d2-27cd-5a5e-8efc-080ba80cf258

.PHONY: free-vm02
free-vm02:
	@$(MAKE) --no-print-directory _free_vm VM_NAME=vm02 MACHINE_UUID=2294c949-88f6-5390-8154-fa53d93a3313

.PHONY: free-vm03
free-vm03:
	@$(MAKE) --no-print-directory _free_vm VM_NAME=vm03 MACHINE_UUID=2a92f14d-d3b1-4d46-b813-5d058103743e

.PHONY: _console-vm
_console-vm:
	@echo "exit console with CTRL+5 and then quit telnet through q + ENTER"
	@docker exec -it vms telnet 127.0.0.1 $(CONSOLE_PORT)

.PHONY: console-vm01
console-vm01:
	@$(MAKE) --no-print-directory _console-vm	CONSOLE_PORT=4000

.PHONY: console-vm02
console-vm02:
	@$(MAKE) --no-print-directory _console-vm	CONSOLE_PORT=4001

.PHONY: console-vm03
console-vm03:
	@$(MAKE) --no-print-directory _console-vm	CONSOLE_PORT=4002

## SSH TARGETS FOR MACHINES ##
# Python code could be replaced by jq, but it is not preinstalled on Cumulus
define get-ipv6-link-local-address
	$(shell ssh -F files/ssh/config leaf01 "vtysh -c 'show bgp $(if $(2),vrf $(2) )neighbors $(1) json' | \
	python3 -c 'import sys, json; data = json.load(sys.stdin); key = next(iter(data)); print(data[key][\"bgpNeighborAddr\"] + \"%\" + key)'" \
	)
endef

.PHONY: ssh-firewall
ssh-firewall:
	$(eval address = $(call get-ipv6-link-local-address,firewall))
	ssh -F files/ssh/config $(address) $(COMMAND)

.PHONY: ssh-machine01
ssh-machine01:
	$(eval address = $(call get-ipv6-link-local-address,machine01,$(VRF)))
	ssh -F files/ssh/config $(address) $(COMMAND)

.PHONY: ssh-machine02
ssh-machine02:
	$(eval address = $(call get-ipv6-link-local-address,machine02,$(VRF)))
	ssh -F files/ssh/config $(address) $(COMMAND)

.PHONY: connect-to-cloudflare
connect-to-cloudflare:
	@echo "Attempting to connect to Cloudflare..."
	@for i in $$(seq 1 $(MAX_RETRIES)); do \
		if $(MAKE) ssh-machine01 COMMAND="sudo curl --connect-timeout 1 --fail --silent https://1.1.1.1" > /dev/null 2>&1; then \
			echo "Connected successfully"; \
			exit 0; \
		else \
			echo "Connection failed"; \
			if [ $$i -lt $(MAX_RETRIES) ]; then \
				echo "Retrying in 2 seconds..."; \
				sleep 2; \
			else \
				echo "Max retries reached"; \
				exit 1; \
			fi; \
		fi; \
	done

## DEV TARGETS ##

.PHONY: dev-env
dev-env:
	@echo "export METALCTL_API_URL=http://api.172.17.0.1.nip.io:8080/metal"
	@echo "export METALCTL_HMAC=metal-admin"
	@echo "export KUBECONFIG=$(KUBECONFIG)"
