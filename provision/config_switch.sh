#!/bin/bash

echo "#################################"
echo "  Running Switch Post Config (config_switch.sh)"
echo "#################################"
sudo su


## Convenience code. This is normally done in ZTP.

# Make DHCP occur without delays
echo "retry 1;" >> /etc/dhcp/dhclient.conf


echo "#################################"
echo "   Finished"
echo "#################################"
