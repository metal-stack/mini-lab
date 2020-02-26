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
run: _fetch-metalctl-image-tag
	docker-compose up
	vagrant up machine01 machine02

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
dev: build-hammer-initrd build-api-image registry build-core-image caddy restart-dev

.PHONY: restart-dev
restart-dev: cleanup bake _enable-dev run

.PHONY: down-dev
restart-dev: caddy-down registry-down down

.PHONY: _enable-dev
_enable-dev: _fetch-metalctl-image-tag
	@echo "EXTRA_VARS=-e @files/dev_images.yaml" >> .env
	kind load docker-image metalstack/metal-api:dev

.PHONY: registry-down
registry-down:
	-@docker rm -f registry > /dev/null 2>&1

.PHONY: registry
registry: registry-down
	docker run -p 5000:443 -v $(shell pwd)/files/certs/registry:/certs -e REGISTRY_HTTP_ADDR=0.0.0.0:443 -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/ca.pem -e REGISTRY_HTTP_TLS_KEY=/certs/ca-key.pem --name registry -d registry:2
	@make --no-print-directory push-core-image

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
	-@docker rm -f caddy > /dev/null 2>&1

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
