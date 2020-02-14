MAKEFLAGS += -j2

.PHONY: up
up: control-plane-bake partition-bake
	docker-compose up
	vagrant up machine01 machine02

.PHONY: control-plane-bake
control-plane-bake:
	kind create cluster \
		--config control-plane/kind.yaml \
		--kubeconfig .kubeconfig || true

.PHONY: control-plane-deploy
control-plane-deploy: control-plane-bake
	docker-compose up control-plane

.PHONY: partition-bake
partition-bake:
	vagrant up

.PHONY: partition-deploy
partition-deploy: partition-bake
	docker-compose up partition
	vagrant up machine01 machine02

.PHONY: cleanup
cleanup:
	vagrant destroy -f --parallel || true
	kind delete cluster
	rm -f .kubeconfig
	rm -f .ansible_vagrant_cache
