# Deployment Flow

0. load env variables from release vector
    - `make env`
    - runs ./env.sh

1. generate certs
    - `make gen-certs`

1. Metalstack controlplane
    - Create kind cluster
        - `make control-plane-bake`
        - kind config: ./control-plane/kind.yaml
    - Create Proxy Registries
        - `make create-proxy-registries`
        - docker containers defined in ./compose.yaml
    - Install Metalstack Control Plane
        - `make control-plane`
        -  control-plane in ./compose.yaml
        - runs ansible playbook ./deploy_control_plane.yaml


# Architecture / Concepts / Birds Eye View


## Which flavors / how does the setup exactly look like?
Which problems do those problems solve for the user?


### Kamaji

Runs a kind cluster next to a metal-stack partition, with the metal-stack control plane running inside the kind cluster.
Launches a Kamaji 

- run it from github.com/metal-stack/cluster-api-provider-metal-stack
- set flavor to "kamaji"

### CAPI
- run it from github.com/metal-stack/cluster-api-provider-metal-stack
- set flavor to "capi"


# Machines

The machines are OCI containers that run and ipmi_sim to provide a virtual IPMI and launch the machine using QEMU

Access is possible using ipmi_tool. (TODO command)

# Operator

## How to access leafs

Use ssh to access leafs. (We cannot access them via docker, as they run inside the qemu vm)
```
ssh -F files/ssh/config leaf01
```

Use `vtysh` to configure frr.

## Access machines and firewalls

Use the ipmi console to access the machines and firewalls.
TODO maybe introduce ssh support as well? But this could mean we have to introduce ignition configs and a lot of extra work, so maybe not worth it for now.

```
# firewalls need a password to be accessed via user metal, skip this one for machines
make password-machine01

make console-machine01
```

# Notes

- *-bake naming is confusing. Bake implies that there is something there already
- the makefile is confusing to understand, maybe move everything possible into ansible

# Troubleshooting

## File descriptors

## Log into ghcr.io and docker hub

## How to the mini-lab with a firewall

## Sonic switches become unavailable after reboot

likely: [roles/sonic/tasks/main.yaml](roles/sonic/tasks/main.yaml)

TODO: make config part of persistent sonic configuration