# Virtual Sonic Images

We use sonic-vpp to emulate SONiC switches. It is running in kvm inside a containerlab container. To provide better emulation accuracy we use sonic-vpp, which used the Vector Package Processor to emulate somthing like a switch ASIC, like the Broadcom Tomahawk 3 used in our Edgecore Accton AS7726-X32 workhorse we use in production. We migrated to sonic-vpp because the sonic-vs image used mostly netlink primitives, which behaved differently than an ASIC driven through SONiCs SAI layer.  It's slower but still sane.


# Configuration knobs

You can edit the port_config.ini to add more ports.


# Boot process
The switch will boot with a default first-boot configuration. This is required since first boot will generate some required configuration for VPP. After a short while the configuration that is generated in launch.py is injected and the sonic is reloaded. After the new configuration is loaded the container will be marked ready. Check the docker logs for errors if bootup takes more than a minute. 