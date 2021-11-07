.DEFAULT_GOAL := up
.EXPORT_ALL_VARIABLES:

KUBECONFIG := $(shell pwd)/.kubeconfig
MINI_LAB_FLAVOR := $(or $(MINI_LAB_FLAVOR),default)

MINI_LAB_VM_IMAGE := $(or $(MINI_LAB_VM_IMAGE),ghcr.io/metal-stack/mini-lab-vms:latest)

# Default values
DOCKER_COMPOSE_OVERRIDE=

# Machine flavors
MACHINE_OS=ubuntu-20.04
ifeq ($(MINI_LAB_FLAVOR),default)
VAGRANT_MACHINES=machine01 machine02
else ifeq ($(MINI_LAB_FLAVOR),cluster-api)
VAGRANT_MACHINES=machine01 machine02 machine03
else
$(error Unknown flavor $(MINI_LAB_FLAVOR))
endif

# Commands
YQ=docker run --rm -i -v $(shell pwd):/workdir mikefarah/yq:3 /bin/sh -c

.PHONY: up
up: env control-plane-bake partition-bake
	docker-compose up --remove-orphans --force-recreate control-plane partition
	@$(MAKE) --no-print-directory reboot-machine01
	@$(MAKE) --no-print-directory reboot-machine02

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

.PHONY: route
route: _ips
	eval "sudo ip r a ${staticR}"

.PHONY: fwrules
fwrules: _ips
	eval "sudo -- iptables -I LIBVIRT_FWO -s 100.255.254.0/24 -i docker0 -j ACCEPT;"
	eval "sudo -- iptables -I LIBVIRT_FWO -s 10.0.1.0/24 -i docker0 -j ACCEPT;"
	eval "sudo -- iptables -I LIBVIRT_FWI -d 100.255.254.0/24 -o docker0 -j ACCEPT;"
	eval "sudo -- iptables -I LIBVIRT_FWI -d 10.0.1.0/24 -o docker0 -j ACCEPT;"
	eval "sudo -- iptables -t nat -I LIBVIRT_PRT -s 100.255.254.0/24 ! -d 100.255.254.0/24 -j MASQUERADE"
	eval "sudo -- iptables -t nat -I LIBVIRT_PRT -s 10.0.1.0/24 ! -d 10.0.1.0/24 -j MASQUERADE"

.PHONY: cleanup
cleanup: caddy-down registry-down cleanup-control-plane cleanup-partition

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
	docker-compose run metalctl network list --name user-private-network | grep user-private-network || docker-compose run metalctl network allocate --partition mini-lab --project 00000000-0000-0000-0000-000000000000 --name user-private-network

.PHONY: machine
machine: _privatenet
	docker-compose run metalctl machine create --description test --name test --hostname test --project 00000000-0000-0000-0000-000000000000 --partition mini-lab --image $(MACHINE_OS) --size v1-small-x86 --networks $(shell docker-compose run metalctl network list --name user-private-network -o template --template '{{ .id }}')

.PHONY: firewall
firewall: _ips _privatenet
	docker-compose run metalctl firewall create --description fw --name fw --hostname fw --project 00000000-0000-0000-0000-000000000000 --partition mini-lab --image firewall-ubuntu-2.0 --size v1-small-x86 --networks internet-vagrant-lab,$(shell docker-compose run metalctl network list --name user-private-network -o template --template '{{ .id }}')

.PHONY: ls
ls: env
	docker-compose run metalctl machine ls

## SWITCH MANAGEMENT ##

.PHONY: ssh-leaf01
ssh-leaf01:
	ssh -o StrictHostKeyChecking=no -i files/ssh/id_rsa root@mini-lab-leaf01

.PHONY: ssh-leaf02
ssh-leaf02:
	ssh -o StrictHostKeyChecking=no -i files/ssh/id_rsa root@mini-lab-leaf02

## MACHINE MANAGEMENT ##

.PHONY: reboot-machine
reboot-machine:
	docker exec mini-lab-vms /kill_vm.sh $(MACHINE_UUID)
	docker exec mini-lab-vms /create_vm.sh $(MACHINE_UUID)

.PHONY: reboot-machine01
reboot-machine01:
	@$(MAKE)	--no-print-directory	reboot-machine	MACHINE_UUID=e0ab02d2-27cd-5a5e-8efc-080ba80cf258

.PHONY: reboot-machine02
reboot-machine02:
	@$(MAKE)	--no-print-directory	reboot-machine	MACHINE_UUID=2294c949-88f6-5390-8154-fa53d93a3313

.PHONY: password
password: env
	docker-compose run metalctl machine consolepassword $(MACHINE_UUID)

.PHONY: password-machine01
password-machine01:
	@$(MAKE)	--no-print-directory	password	MACHINE_UUID=e0ab02d2-27cd-5a5e-8efc-080ba80cf258

.PHONY: password-machine02
password-machine02:
	@$(MAKE)	--no-print-directory	password	MACHINE_UUID=2294c949-88f6-5390-8154-fa53d93a3313

.PHONY: delete-machine
delete-machine:
	docker-compose run metalctl machine rm $(MACHINE_UUID)
	@$(MAKE) --no-print-directory reboot-machine	MACHINE_UUID=$(MACHINE_UUID)

.PHONY: delete-machine01
delete-machine01: env
	@$(MAKE) --no-print-directory delete-machine	MACHINE_UUID=e0ab02d2-27cd-5a5e-8efc-080ba80cf258

.PHONY: delete-machine02
delete-machine02: env
	@$(MAKE) --no-print-directory delete-machine	MACHINE_UUID=2294c949-88f6-5390-8154-fa53d93a3313

.PHONY: console-machine
console-machine:
	@echo "exit console with CTRL+5"
	@docker exec -it mini-lab-vms telnet 127.0.0.1 $(CONSOLE_PORT)

.PHONY: console-machine01
console-machine01:
	@$(MAKE) --no-print-directory console-machine	CONSOLE_PORT=4000

.PHONY: console-machine02
console-machine02:
	@$(MAKE) --no-print-directory console-machine	CONSOLE_PORT=4001

.PHONY: reinstall-machine01
reinstall-machine01: env
	docker-compose run metalctl machine reinstall --image ubuntu-20.04 e0ab02d2-27cd-5a5e-8efc-080ba80cf258
	@$(MAKE) --no-print-directory reboot-machine01

.PHONY: reinstall-machine02
reinstall-machine02: env
	docker-compose run metalctl machine reinstall --image ubuntu-20.04 2294c949-88f6-5390-8154-fa53d93a3313
	@$(MAKE) --no-print-directory reboot-machine02

## DEV TARGETS ##

.PHONY: dev-env
dev-env:
	@echo "export METALCTL_URL=http://api.0.0.0.0.nip.io:8080/metal"
	@echo "export METALCTL_HMAC=metal-admin"
	@echo "export KUBECONFIG=$(KUBECONFIG)"

.PHONY: build-vms-image
build-vms-image:
	cd images && docker build -f Dockerfile.vms -t $(MINI_LAB_VM_IMAGE) . && cd -

.PHONY: dev
dev: caddy registry build-hammer-initrd build-api-image build-core-image push-core-image control-plane-bake load-api-image
	docker-compose -f docker-compose.yml -f docker-compose.dev.yml up
	vagrant up $(VAGRANT_MACHINES)

.PHONY: load-api-image
load-api-image:
	kind --name metal-control-plane load docker-image ghcr.io/metal-stack/metal-api:dev

.PHONY: registry-down
registry-down:
	@docker rm -f registry > /dev/null 2>&1 || true

.PHONY: registry
registry: registry-down
	docker run -p 5000:443 -v $(shell pwd)/files/certs/registry:/certs -e REGISTRY_HTTP_ADDR=0.0.0.0:443 -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/ca.pem -e REGISTRY_HTTP_TLS_KEY=/certs/ca-key.pem --name registry -d registry:2

.PHONY: reload-api
reload-api: build-api-image load-api-image
	kubectl --kubeconfig=$(KUBECONFIG) --namespace metal-control-plane delete pod -l app=metal-api

.PHONY: build-api-image
build-api-image:
	docker build -t ghcr.io/metal-stack/metal-api:dev ../metal-api

.PHONY: _ips
_ips:
	$(eval ipL1 = $(shell ${YQ} "yq r mini-lab/ansible-inventory.yml 'all.children.cvx.hosts.mini-lab-leaf01.ansible_host'"))
	$(eval ipL2 = $(shell ${YQ} "yq r mini-lab/ansible-inventory.yml 'all.children.cvx.hosts.mini-lab-leaf02.ansible_host'"))
	$(eval staticR = "100.255.254.0/24 nexthop via $(ipL1) dev docker0 nexthop via $(ipL2) dev docker0")

.PHONY: reload-core
reload-core: build-core-image push-core-image _ips
	ssh -i files/ssh/id_rsa root@${ipL1} "sudo docker pull 172.17.0.1:5000/metalstack/metal-core:dev; sudo systemctl restart metal-core"
	ssh -i files/ssh/id_rsa root@${ipL2} "sudo docker pull 172.17.0.1:5000/metalstack/metal-core:dev; sudo systemctl restart metal-core"

.PHONY: build-core-image
build-core-image:
	docker build -t localhost:5000/metalstack/metal-core:dev ../metal-core

.PHONY: push-core-image
push-core-image:
	docker push localhost:5000/metalstack/metal-core:dev

.PHONY: caddy-down
caddy-down:
	@docker rm -f caddy > /dev/null 2>&1 || true

.PHONY: caddy
caddy: caddy-down
	docker run -v $(shell pwd):/srv -p 20015:2015 --name caddy -d abiosoft/caddy

.PHONY: build-hammer-image
build-hammer-image:
	docker build -t metalstack/metal-hammer:dev ../metal-hammer

.PHONY: build-hammer-initrd
build-hammer-initrd: build-hammer-image
	docker export $(shell docker create metalstack/metal-hammer:dev /dev/null) > metal-hammer.tar
	tar -xf metal-hammer.tar metal-hammer-initrd.img.lz4
	@rm -f metal-hammer.tar
	md5sum metal-hammer-initrd.img.lz4 > metal-hammer-initrd.img.lz4.md5
