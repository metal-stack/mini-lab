.DEFAULT_GOAL := up

.PHONY: up
up: bake run

.PHONY: restart
restart: down up

.PHONY: down
down: cleanup

.PHONY: bake
bake: control-plane-bake partition-bake

.PHONY: run
run: compose-up vagrant-up

.PHONY: compose-up
compose-up: _fetch-metalctl-image-tag
	docker-compose up

.PHONY: vagrant-up
vagrant-up:
	vagrant up machine01 machine02

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

.PHONY: reboot-machine01
reboot-machine01:
	vagrant destroy -f machine01
	vagrant up machine01

.PHONY: reboot-machine02
reboot-machine02:
	vagrant destroy -f machine02
	vagrant up machine02

.PHONY: _fetch-metalctl-image-tag
_fetch-metalctl-image-tag:
	@echo "METALCTL_IMAGE_TAG=$(shell cat group_vars/minilab/images.yaml | grep metal_metalctl_image_tag: | cut -d: -f2 | sed 's/ //g')" > .env

# ---- development targets -------------------------------------------------------------
 
.PHONY: dev
dev: cleanup caddy registry build-hammer-initrd build-api-image build-core-image push-core-image bake load-api-image compose-up-dev vagrant-up

.PHONY: down-dev
down-dev: caddy-down registry-down down

.PHONY: compose-up-dev
compose-up-dev: _fetch-metalctl-image-tag
	docker-compose -f docker-compose.yml -f docker-compose.dev.yml up

.PHONY: load-api-image
load-api-image:
	kind load docker-image metalstack/metal-api:dev

.PHONY: registry-down
registry-down:
	@docker rm -f registry > /dev/null 2>&1 || true

.PHONY: registry
registry: registry-down
	docker run -p 5000:443 -v $(shell pwd)/files/certs/registry:/certs -e REGISTRY_HTTP_ADDR=0.0.0.0:443 -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/ca.pem -e REGISTRY_HTTP_TLS_KEY=/certs/ca-key.pem --name registry -d registry:2

.PHONY: build-api-image
build-api-image:
	docker build -t metalstack/metal-api:dev ../metal-api

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
	docker run -v $(shell pwd):/srv -p 2015:2015 --name caddy -d abiosoft/caddy

.PHONY: build-hammer-image
build-hammer-image:
	docker build -t metalstack/metal-hammer:dev ../metal-hammer

.PHONY: build-hammer-initrd
build-hammer-initrd: build-hammer-image
	docker export $(shell docker create metalstack/metal-hammer:dev /dev/null) > metal-hammer.tar
	tar -xf metal-hammer.tar metal-hammer-initrd.img.lz4
	@rm -f metal-hammer.tar
	md5sum metal-hammer-initrd.img.lz4 > metal-hammer-initrd.img.lz4.md5
