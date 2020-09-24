.DEFAULT_GOAL := up

KUBECONFIG := $(shell pwd)/.kubeconfig

.PHONY: up
up: bake env
	docker-compose up --remove-orphans --force-recreate control-plane partition && vagrant up machine01 machine02

.PHONY: restart
restart: down up

.PHONY: down
down: cleanup

.PHONY: bake
bake: control-plane-bake partition-bake

.PHONY: control-plane-bake
control-plane-bake:
	@if ! which kind > /dev/null; then echo "kind needs to be installed"; exit 1; fi
	@if ! kind get clusters | grep metal-control-plane > /dev/null; then \
		kind create cluster \
		  --name metal-control-plane \
			--config control-plane/kind.yaml \
			--kubeconfig $(KUBECONFIG); fi

.PHONY: control-plane
control-plane: control-plane-bake env
	docker-compose up --remove-orphans --force-recreate control-plane

.PHONY: partition-bake
partition-bake:
ifeq (,$(wildcard ./.vagrant_version_host_system))
	@vagrant version | grep "Installed Version" | cut -d: -f 2 | tr -d '[:space:]' > .vagrant_version_host_system
endif
	vagrant up

.PHONY: partition
partition: partition-bake
	docker-compose up --remove-orphans --force-recreate partition && vagrant up machine01 machine02

.PHONY: route
route: _ips
	@echo "sudo ip r a $(staticR)"

.PHONY: cleanup
cleanup: caddy-down registry-down
	vagrant destroy -f --parallel || true
	kind delete cluster --name metal-control-plane
	docker-compose down
	rm -f $(KUBECONFIG)
	rm -f .vagrant_version_host_system
	rm -f .ansible_vagrant_cache

.PHONY: dev-env
dev-env:
	@echo "export METALCTL_URL=http://api.0.0.0.0.xip.io:8080/metal"
	@echo "export METALCTL_HMAC=metal-admin"
	@echo "export KUBECONFIG=$(KUBECONFIG)"

.PHONY: reboot-machine01
reboot-machine01:
	vagrant destroy -f machine01
	vagrant up machine01

.PHONY: reboot-machine02
reboot-machine02:
	vagrant destroy -f machine02
	vagrant up machine02

.PHONY: password01
password01: env
	docker-compose run metalctl machine ls --id e0ab02d2-27cd-5a5e-8efc-080ba80cf258 -o template --template "{{ .allocation.console_password }}"

.PHONY: password02
password02: env
	docker-compose run metalctl machine ls --id 2294c949-88f6-5390-8154-fa53d93a3313 -o template --template "{{ .allocation.console_password }}"

.PHONY: _privatenet
_privatenet: env
	docker-compose run metalctl network list --name user-private-network | grep user-private-network || docker-compose run metalctl network allocate --partition vagrant --project 00000000-0000-0000-0000-000000000000 --name user-private-network

.PHONY: machine
machine: _privatenet
	docker-compose run metalctl machine create --description test --name test --hostname test --project 00000000-0000-0000-0000-000000000000 --partition vagrant --image ubuntu-20.04 --size v1-small-x86 --networks $(shell docker-compose run metalctl network list --name user-private-network -o template --template '{{ .id }}')

.PHONY: firewall
firewall: _ips _privatenet
	docker-compose run metalctl firewall create --description fw --name fw --hostname fw --project 00000000-0000-0000-0000-000000000000 --partition vagrant --image firewall-ubuntu-2.0 --size v1-small-x86 --networks internet-vagrant-lab,$(shell docker-compose run metalctl network list --name user-private-network -o template --template '{{ .id }}')

.PHONY: reinstall-machine01
reinstall-machine01: env
	docker-compose run metalctl machine reinstall --image ubuntu-20.04 e0ab02d2-27cd-5a5e-8efc-080ba80cf258
	@$(MAKE) --no-print-directory reboot-machine01

.PHONY: reinstall-machine02
reinstall-machine02: env
	docker-compose run metalctl machine reinstall --image ubuntu-20.04 2294c949-88f6-5390-8154-fa53d93a3313
	@$(MAKE) --no-print-directory reboot-machine02

.PHONY: delete-machine01
delete-machine01: env
	docker-compose run metalctl machine rm e0ab02d2-27cd-5a5e-8efc-080ba80cf258
	@$(MAKE) --no-print-directory reboot-machine01

.PHONY: delete-machine02
delete-machine02: env
	docker-compose run metalctl machine rm 2294c949-88f6-5390-8154-fa53d93a3313
	@$(MAKE) --no-print-directory reboot-machine02

.PHONY: console-machine01
console-machine01:
	@echo "exit console with CTRL+5"
	virsh console metalmachine01

.PHONY: console-machine02
console-machine02:
	@echo "exit console with CTRL+5"
	virsh console metalmachine02

.PHONY: ls
ls: env
	docker-compose run metalctl machine ls

.PHONY: env
env:
	./env.sh

# ---- development targets -------------------------------------------------------------

.PHONY: dev
dev: caddy registry build-hammer-initrd build-api-image build-core-image push-core-image control-plane-bake load-api-image partition-bake
	docker-compose -f docker-compose.yml -f docker-compose.dev.yml up
	vagrant up machine01 machine02

.PHONY: load-api-image
load-api-image:
	kind --name metal-control-plane load docker-image metalstack/metal-api:dev

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
	docker build -t metalstack/metal-api:dev ../metal-api

.PHONY: _ips
_ips:
	$(eval dev = $(shell virsh net-info vagrant-libvirt | grep Bridge | cut -d' ' -f10 2>/dev/null))
	$(eval ipL1 = $(shell python3 -c 'import pickle; print(pickle.load(open(".ansible_vagrant_cache", "rb"))["meta_vars"]["leaf01"]["ansible_host"])'))
	$(eval ipL2 = $(shell python3 -c 'import pickle; print(pickle.load(open(".ansible_vagrant_cache", "rb"))["meta_vars"]["leaf02"]["ansible_host"])'))
	$(eval staticR = "100.255.254.0/24 nexthop via $(ipL1) dev $(dev) nexthop via $(ipL2) dev $(dev)")

.PHONY: reload-core
reload-core: build-core-image push-core-image _ips
	ssh -i .vagrant/machines/leaf01/libvirt/private_key vagrant@${ipL1} "sudo docker pull 192.168.121.1:5000/metalstack/metal-core:dev; sudo systemctl restart metal-core"
	ssh -i .vagrant/machines/leaf02/libvirt/private_key vagrant@${ipL2} "sudo docker pull 192.168.121.1:5000/metalstack/metal-core:dev; sudo systemctl restart metal-core"

.PHONY: ssh-leaf01
ssh-leaf01: _ips
	ssh -i .vagrant/machines/leaf01/libvirt/private_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null vagrant@${ipL1} -t "sudo -i"

.PHONY: ssh-leaf02
ssh-leaf02: _ips
	ssh -i .vagrant/machines/leaf02/libvirt/private_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null vagrant@${ipL2} -t "sudo -i"

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
