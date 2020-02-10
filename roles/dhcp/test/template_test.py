import unittest

from test import read_template_file

from ansible.template import Templar


class DHCPD(unittest.TestCase):
    def test_dhcpd_config_template(self):
        dhcpd_conf = read_template_file("dhcpd.conf.j2")

        templar = Templar(loader=None, variables=dict(
            dhcp_server_net="1.2.3.4",
            dhcp_range_min="1",
            dhcp_range_max="2",
            dhcp_server_ip="2.2.2.2",
            groups=dict(mgmt_servers=["mgmt01", "mgmt02"]),
            hostvars=dict(mgmt01=dict(switch_mgmt_ip="3.3.3.3"), mgmt02=dict(switch_mgmt_ip="4.4.4.4")),
            dhcp_public_dns_servers_fallback=["1.1.1.1", "8.8.8.8"]
        ))

        res = templar.template(dhcpd_conf)

        self.assertIn("option domain-name-servers 3.3.3.3, 4.4.4.4;", res)

    def test_dhcpd_config_template_fallback(self):
        dhcpd_conf = read_template_file("dhcpd.conf.j2")

        templar = Templar(loader=None, variables=dict(
            dhcp_server_net="1.2.3.4",
            dhcp_range_min="1",
            dhcp_range_max="2",
            dhcp_server_ip="2.2.2.2",
            groups=dict(),
            dhcp_public_dns_servers_fallback=["1.1.1.1", "8.8.8.8"]
        ))

        res = templar.template(dhcpd_conf)

        self.assertIn("option domain-name-servers 1.1.1.1, 8.8.8.8;", res)
