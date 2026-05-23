# Virtual Sonic Images

We use sonic-vpp to emulate SONiC switches. It is running in kvm inside a containerlab container. To provide better emulation accuracy we use sonic-vpp, which used the Vector Package Processor to emulate somthing like a switch ASIC, like the Broadcom Tomahawk 3 used in our Edgecore Accton AS7726-X32 workhorse we use in production. We migrated to sonic-vpp because the sonic-vs image used mostly netlink primitives, which behaved differently than an ASIC driven through SONiCs SAI layer.  It's slower but still sane.


# Configuration knobs

You can edit the port_config.ini to add more ports. Keep the number as low as possible. It will put less strain on your system because it will spawn fewer VPP worker threads. You will have to set up the switch from scratch afterwards, since VPP will generate some configuration on first startup.