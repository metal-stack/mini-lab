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
