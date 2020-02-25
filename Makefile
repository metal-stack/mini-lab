MAKEFLAGS += -j2

.DEFAULT_GOAL := up

.PHONY: up
up: control-plane-bake partition-bake
	docker-compose up
	vagrant up machine01 machine02

.PHONY: down
down: cleanup

.PHONY: control-plane-bake
control-plane-bake:
	kind create cluster \
		--config control-plane/kind.yaml \
		--kubeconfig .kubeconfig || true

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
	vagrant destroy -f --parallel || true
	kind delete cluster
	docker-compose down
	rm -f .kubeconfig
	rm -f .ansible_vagrant_cache

.PHONY: dev
dev: build-hammer-initrd caddy up

.PHONY: caddy
caddy:
	@docker rm -f caddy > /dev/null 2>&1 || true
	docker run -v $(shell pwd):/srv -p 2015:2015 --name caddy -d abiosoft/caddy

.PHONY: build-hammer-initrd
build-hammer-initrd:
	@docker build -t metal-hammer ../metal-hammer
	@docker export $(shell docker create metal-hammer /dev/null) > metal-hammer.tar
	@tar -xf metal-hammer.tar metal-hammer-initrd.img.lz4
	@rm -f metal-hammer.tar
	@md5sum metal-hammer-initrd.img.lz4 > metal-hammer-initrd.img.lz4.md5
