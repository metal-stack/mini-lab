# Dev Instructions

To simplify developing changes for the `metal-api`, `metal-hammer` and `metal-core`, it is possible to use development artifacts from within the mini-lab.

Also start the mini-lab with a kind cluster, a metal-api instance
as well as some vagrant VMs with two leaf switches and two machine skeletons.
Additionally a Caddy and a Docker registry container is started.
The former serves a prebuilt `metal-hammer-initrd` image, the latter holds
prebuilt `metalstack/metal-api` and `metalstack/metal-core` images,
which will be used as replacements for the official ones.

Thus you have to clone the following **metal-stack** repositories:

## Prerequisites:

```shell script
git clone https://github.com/metal-stack/metal-hammer ../metal-hammer
git clone https://github.com/metal-stack/metal-api ../metal-api
git clone https://github.com/metal-stack/metal-core ../metal-core
```

## Start/Restart/Stop:

Build `metal-hammer-initrd`, `metalstack/metal-api` and `metalstack/metal-core` images and start
a minimal metal-stack system as well as a Caddy container that servers the former one
and a Docker registry that holds the latter ones:

```shell script
make dev
```

Restart a potentially running metal-stack development system without rebuilding images
and without stopping the local Caddy and Docker registry containers:

```shell script
make restart-dev
```

Stop and cleanup a potentially running metal-stack development system
as well as the local Caddy and Docker registry containers:

```shell script
make down-dev
```
