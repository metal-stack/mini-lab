.DEFAULT_GOAL := up

.PHONY: up
up: control-plane-bake partition-bake
	docker-compose up
	vagrant up machine01 machine02

.PHONY: down
down: cleanup

.PHONY: control-plane-bake
control-plane-bake:
	-kind create cluster \
		--config control-plane/kind.yaml \
		--kubeconfig .kubeconfig

.PHONY: control-plane
control-plane: control-plane-bake
	docker-compose up control-plane

.PHONY: partition-bake
partition-bake:
	vagrant up

.PHONY: partition
partition: partition-bake
	docker-compose up partition
	vagrant up machine01 machine02

.PHONY: cleanup
cleanup:
	-vagrant destroy -f --parallel
	kind delete cluster
	docker-compose down
	rm -f .kubeconfig
	rm -f .ansible_vagrant_cache

.PHONY: dev
dev: cleanup dev-registry api-image core-image build-hammer-initrd caddy up

.PHONY: dev-registry
dev-registry:
	-@docker rm -f registry > /dev/null 2>&1
	docker run -p 5000:443 -v $(shell pwd)/files/certs/registry:/certs -e REGISTRY_HTTP_ADDR=0.0.0.0:443 -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/ca.pem -e REGISTRY_HTTP_TLS_KEY=/certs/ca-key.pem --name registry -d registry:2

.PHONY: caddy
caddy:
	-@docker rm -f caddy > /dev/null 2>&1
	docker run -v $(shell pwd):/srv -p 2015:2015 --name caddy -d abiosoft/caddy

.PHONY: hammer-image
hammer-image:
	docker build -t metalstack/metal-hammer:dev ../metal-hammer

.PHONY: api-image
api-image:
	docker build -t localhost:5000/metalstack/metal-api:dev ../metal-api
	docker push localhost:5000/metalstack/metal-api:dev

.PHONY: core-image
core-image:
	docker build -t localhost:5000/metalstack/metal-core:dev ../metal-core
	docker push localhost:5000/metalstack/metal-core:dev

.PHONY: build-hammer-initrd
build-hammer-initrd: hammer-image
	docker export $(shell docker create metalstack/metal-hammer:dev /dev/null) > metal-hammer.tar
	tar -xf metal-hammer.tar metal-hammer-initrd.img.lz4
	@rm -f metal-hammer.tar
	md5sum metal-hammer-initrd.img.lz4 > metal-hammer-initrd.img.lz4.md5

.PHONY: reboot-machine01
reboot-machine01:
	vagrant destroy -f machine01
	vagrant up machine01

.PHONY: reboot-machine02
reboot-machine02:
	vagrant destroy -f machine02
	vagrant up machine02
