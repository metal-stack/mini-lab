.DEFAULT_GOAL := up
.EXPORT_ALL_VARIABLES:

-include .env

# Commands
YQ=docker run --rm -i -v $(shell pwd):/workdir mikefarah/yq:4

KINDCONFIG := $(or $(KINDCONFIG),control-plane/kind.yaml)
KUBECONFIG := $(shell pwd)/.kubeconfig

METALCTL_HMAC := $(or $(METALCTL_HMAC),metal-admin)
METALCTL_API_URL := $(or $(METALCTL_API_URL),http://api.172.17.0.1.nip.io:8080/metal)

MKE2FS_CONFIG := $(shell pwd)/mke2fs.conf
# Default values
CONTAINERLAB=$(shell which containerlab)

# extra vars can be used by projects that built on the mini-lab, which want to override default configuration
ANSIBLE_EXTRA_VARS_FILE := $(or $(ANSIBLE_EXTRA_VARS_FILE),)

MINI_LAB_FLAVOR := $(or $(MINI_LAB_FLAVOR),sonic)
MINI_LAB_VM_IMAGE := $(or $(MINI_LAB_VM_IMAGE),ghcr.io/metal-stack/mini-lab-vms:latest)
MINI_LAB_SONIC_IMAGE := $(or $(MINI_LAB_SONIC_IMAGE),ghcr.io/metal-stack/mini-lab-sonic:latest)

MACHINE_OS=debian-12.0
MAX_RETRIES := 30

# Machine flavors
ifeq ($(MINI_LAB_FLAVOR),cumulus)
MACHINE_OS=ubuntu-24.4
LAB_TOPOLOGY=mini-lab.cumulus.yaml
VRF=vrf20
else ifeq ($(MINI_LAB_FLAVOR),sonic)
LAB_TOPOLOGY=mini-lab.sonic.yaml
VRF=Vrf20
else ifeq ($(MINI_LAB_FLAVOR),capms)
LAB_TOPOLOGY=mini-lab.capms.yaml
VRF=Vrf20
else ifeq ($(MINI_LAB_FLAVOR),gardener)
GARDENER_ENABLED=true
# usually gardener restricts the maximum version for k8s:
K8S_VERSION=1.31.6
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
  DOCKER_COMPOSE_RUN_ARG=--no-TTY --rm
else
  DOCKER_COMPOSE_RUN_ARG=--rm
endif

.PHONY: up
up: env gen-certs control-plane-bake partition-bake
	@chmod 600 files/ssh/id_rsa
	docker compose up --abort-on-container-failure --remove-orphans --force-recreate control-plane partition
	@$(MAKE)	--no-print-directory	start-machines
# for some reason an allocated machine will not be able to phone home
# without restarting the metal-core
# TODO: should be investigated and fixed if possible
	sleep 10
	ssh -F files/ssh/config leaf01 'systemctl restart metal-core'
	ssh -F files/ssh/config leaf02 'systemctl restart metal-core'

.PHONY: restart
restart: down up

.PHONY: down
down: cleanup

.PHONY: gen-certs
gen-certs:
	@if ! [ -f "files/certs/ca.pem" ]; then \
		echo "certificate generation required, running cfssl container"; \
		docker run --rm \
			--user $$(id -u):$$(id -g) \
			--entrypoint bash \
			-v ${PWD}:/work \
			cfssl/cfssl /work/scripts/roll_certs.sh; fi

.PHONY: roll-certs
roll-certs:
	rm files/certs/ca.pem
	$(MAKE) gen-certs

.PHONY: control-plane
control-plane: control-plane-bake env
	docker compose up --remove-orphans --force-recreate control-plane

.PHONY: create-proxy-registries
create-proxy-registries:
	docker compose up -d --force-recreate proxy-docker proxy-ghcr proxy-gcr proxy-k8s proxy-quay

.PHONY: control-plane-bake
control-plane-bake: create-proxy-registries
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
ifneq ($(MINI_LAB_FLAVOR),cumulus)
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
			--ip-range=203.0.113.0/26 \
			--ipv6 \
			--gateway=2001:db8::1 \
			--subnet=2001:db8::/48 \
			--opt "com.docker.network.driver.mtu=9000" \
			--opt "com.docker.network.bridge.name=mini_lab_ext" \
			--opt "com.docker.network.bridge.enable_ip_masquerade=true" && \
		sudo ip route add 203.0.113.128/25 via 203.0.113.128 dev mini_lab_ext && \
		sudo ip -6 route add 2001:db8:0:113::/64 via 2001:db8:0:1::1 dev mini_lab_ext; \
	fi

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
	sudo --preserve-env $(CONTAINERLAB) destroy --topo mini-lab.capms.yaml
	docker network rm --force mini_lab_ext

.PHONY: _privatenet
_privatenet: env
	docker compose run $(DOCKER_COMPOSE_RUN_ARG) metalctl network list --name user-private-network | grep user-private-network || docker compose run $(DOCKER_COMPOSE_RUN_ARG) metalctl network allocate --partition mini-lab --project 00000000-0000-0000-0000-000000000001 --name user-private-network

.PHONY: update-userdata
update-userdata:
	cat files/ignition.yaml | docker run --rm -i ghcr.io/metal-stack/metal-deployment-base:$$DEPLOYMENT_BASE_IMAGE_TAG ct | jq > files/ignition.json

.PHONY: machine
machine: _privatenet update-userdata
	docker compose run $(DOCKER_COMPOSE_RUN_ARG) metalctl machine create \
		--description test \
		--name test \
		--hostname test \
		--project 00000000-0000-0000-0000-000000000001 \
		--partition mini-lab \
		--image $(MACHINE_OS) \
		--size v1-small-x86 \
		--userdata "@/tmp/ignition.json" \
		--networks $(shell docker compose run $(DOCKER_COMPOSE_RUN_ARG) metalctl network list --name user-private-network -o template --template '{{ .id }}')

.PHONY: firewall
firewall: _privatenet update-userdata
	docker compose run $(DOCKER_COMPOSE_RUN_ARG) metalctl firewall create \
		--description fw \
		--name fw \
		--hostname fw \
		--project 00000000-0000-0000-0000-000000000001 \
		--partition mini-lab \
		--image firewall-ubuntu-3.0 \
		--size v1-small-x86 \
		--userdata "@/tmp/ignition.json" \
		--firewall-rules-file=/tmp/rules.yaml \
		--networks internet-mini-lab,$(shell docker compose run $(DOCKER_COMPOSE_RUN_ARG) metalctl network list --name user-private-network -o template --template '{{ .id }}')

.PHONY: public-ip
public-ip:
	@docker compose run $(DOCKER_COMPOSE_RUN_ARG) metalctl network ip create --name test --network internet-mini-lab --project 00000000-0000-0000-0000-000000000001 --addressfamily IPv4 -o template --template "{{ .ipaddress }}"

.PHONY: public-ipv6
public-ipv6:
	@docker compose run $(DOCKER_COMPOSE_RUN_ARG) metalctl network ip create --name test --network internet-mini-lab --project 00000000-0000-0000-0000-000000000001 --addressfamily IPv6 -o template --template "{{ .ipaddress }}"

.PHONY: ls
ls: env
	docker compose run $(DOCKER_COMPOSE_RUN_ARG) metalctl machine ls

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
	ssh -F files/ssh/config leaf01

.PHONY: ssh-leaf02
ssh-leaf02:
	ssh -F files/ssh/config leaf02

## MACHINE MANAGEMENT ##
.PHONY: _ipmi_power
_ipmi_power:
	docker exec $(VM) ipmitool -C 3 -I lanplus -U ADMIN -P ADMIN -H 127.0.0.1 chassis power $(COMMAND)

.PHONY: start-machines
start-machines:
	@for i in $$(docker container ps --filter label=clab-node-group=machines --quiet); do \
		$(MAKE) --no-print-directory _ipmi_power VM=$$i COMMAND='on'; \
	done

.PHONY: power-on-machine01
power-on-machine01:
	@$(MAKE) --no-print-directory _ipmi_power VM=machine01 COMMAND=on

.PHONY: power-on-machine02
power-on-machine02:
	@$(MAKE) --no-print-directory _ipmi_power VM=machine02 COMMAND=on

.PHONY: power-on-machine03
power-on-machine03:
	@$(MAKE) --no-print-directory _ipmi_power VM=machine03 COMMAND=on

.PHONY: power-reset-machine01
power-reset-machine01:
	@$(MAKE) --no-print-directory _ipmi_power VM=machine01 COMMAND=reset

.PHONY: power-reset-machine02
power-reset-machine02:
	@$(MAKE) --no-print-directory _ipmi_power VM=machine02 COMMAND=reset

.PHONY: power-reset-machine03
power-reset-machine03:
	@$(MAKE) --no-print-directory _ipmi_power VM=machine03 COMMAND=reset

.PHONY: power-off-machine01
power-off-machine01:
	@$(MAKE) --no-print-directory _ipmi_power VM=machine01 COMMAND=off

.PHONY: power-off-machine02
power-off-machine02:
	@$(MAKE) --no-print-directory _ipmi_power VM=machine02 COMMAND=off

.PHONY: power-off-machine03
power-off-machine03:
	@$(MAKE) --no-print-directory _ipmi_power VM=machine03 COMMAND=off

.PHONY: _console
_console:
	docker exec --interactive --tty $(VM) ipmitool -C 3 -I lanplus -U ADMIN -P ADMIN -H 127.0.0.1 sol activate

.PHONY: console-machine01
console-machine01:
	@$(MAKE) --no-print-directory _console VM=machine01

.PHONY: console-machine02
console-machine02:
	@$(MAKE) --no-print-directory _console VM=machine02

.PHONY: console-machine03
console-machine03:
	@$(MAKE) --no-print-directory _console VM=machine03

.PHONY: _password
_password: env
	docker compose run $(DOCKER_COMPOSE_RUN_ARG) metalctl machine consolepassword $(MACHINE_UUID)

.PHONY: password-machine01
password-machine01:
	@$(MAKE) --no-print-directory _password	MACHINE_NAME=machine01 MACHINE_UUID=00000000-0000-0000-0000-000000000001

.PHONY: password-machine02
password-machine02:
	@$(MAKE) --no-print-directory _password	MACHINE_NAME=machine02 MACHINE_UUID=00000000-0000-0000-0000-000000000002

.PHONY: password-machine0%
password-machine0%:
	@$(MAKE) --no-print-directory _password	MACHINE_NAME=machine0$* MACHINE_UUID=00000000-0000-0000-0000-00000000000$*

## SSH TARGETS FOR MACHINES ##
# Python code could be replaced by jq, but it is not preinstalled on Cumulus
.PHONY: ssh-firewall
ssh-firewall:
	$(eval fw = $(shell ssh -F files/ssh/config leaf01 "vtysh -c 'show bgp neighbors fw json' | \
		python3 -c 'import sys, json; data = json.load(sys.stdin); key = next(iter(data)); print(data[key][\"bgpNeighborAddr\"] + \"%\" + key)'" \
	))
	ssh -F files/ssh/config $(fw) $(COMMAND)

.PHONY: ssh-machine
ssh-machine:
	$(eval machine = $(shell ssh -F files/ssh/config leaf01 "vtysh -c 'show bgp vrf $(VRF) neighbors test json' | \
		python3 -c 'import sys, json; data = json.load(sys.stdin); key = next(iter(data)); print(data[key][\"bgpNeighborAddr\"] + \"%\" + key)'" \
	))
	ssh -F files/ssh/config $(machine) $(COMMAND)

.PHONY: test-connectivity-to-external-service
test-connectivity-to-external-service:
	@for i in $$(seq 1 $(MAX_RETRIES)); do \
		if $(MAKE) ssh-machine COMMAND="sudo curl --connect-timeout 1 --fail --silent http://203.0.113.100" > /dev/null 2>&1; then \
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

.PHONY: test-connectivity-to-external-service-via-ipv6
test-connectivity-to-external-service-via-ipv6:
	@for i in $$(seq 1 $(MAX_RETRIES)); do \
		if $(MAKE) ssh-machine COMMAND="sudo curl --connect-timeout 1 --fail --silent http://[2001:db8::10]" > /dev/null 2>&1; then \
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
	@echo "export METALCTL_API_URL=${METALCTL_API_URL}"
	@echo "export METALCTL_HMAC=${METALCTL_HMAC}"
	@echo "export KUBECONFIG=$(KUBECONFIG)"

## Gardener integration

.PHONY: fetch-virtual-kubeconfig
fetch-virtual-kubeconfig:
	# TODO: it's hard to get the latest issued generic kubeconfig secret... just take the first result for now
	kubectl --kubeconfig=$(KUBECONFIG) get secret -n garden $(shell kubectl --kubeconfig=$(KUBECONFIG) get secret -n garden -l managed-by=secrets-manager,manager-identity=gardener-operator,name=generic-token-kubeconfig --no-headers | awk '{ print $$1 }') -o jsonpath='{.data.kubeconfig}' | base64 -d > .virtual-kubeconfig
	@kubectl --kubeconfig=.virtual-kubeconfig config set-cluster garden --server=https://api.gardener-kube-apiserver.172.17.0.1.nip.io:4443
	@kubectl --kubeconfig=.virtual-kubeconfig config set-credentials garden --token=$(shell kubectl --kubeconfig=$(KUBECONFIG) get secret -n garden shoot-access-virtual-garden -o jsonpath='{.data.token}' | base64 -d)
	@kubectl --kubeconfig=$(KUBECONFIG) config unset users.garden
	@kubectl --kubeconfig=$(KUBECONFIG) config unset contexts.garden
	@kubectl --kubeconfig=$(KUBECONFIG) config unset clusters.garden
	@KUBECONFIG=$(KUBECONFIG):.virtual-kubeconfig kubectl config view --flatten > .merged-kubeconfig
	@rm .virtual-kubeconfig
	@mv .merged-kubeconfig $(KUBECONFIG)
