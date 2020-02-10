from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import subprocess
import sys
import ipaddress

from ansible.errors import AnsibleFilterError
from ansible.module_utils.common.process import get_bin_path
from ansible.module_utils._text import to_text
from ansible.module_utils.six import next


try:
    HAS_HUMANFRIENDLY = True
    import humanfriendly
except ImportError:
    HAS_HUMANFRIENDLY = False

PY2 = sys.version_info[0] == 2


def _decode(value):
    return value if PY2 else value.decode()


def _encode(value):
    return value if PY2 else value.encode()


def parse_size(user_input, binary=False):
    '''https://github.com/xolox/python-humanfriendly'''
    if not HAS_HUMANFRIENDLY:
        raise AnsibleFilterError("humanfriendly needs to be installed")
    return humanfriendly.parse_size(user_input, binary=binary)


def transpile_ignition_config(ignition_config):
    '''https://github.com/coreos/container-linux-config-transpiler'''
    try:
        bin_path = get_bin_path("ct", required=True, opt_dirs=None)
    except ValueError as e:
        raise AnsibleFilterError("ct needs to be installed: %s" % e.message)

    process = subprocess.Popen(["ct"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
    out, err = process.communicate(input=_encode(ignition_config))
    return_code = process.returncode

    if return_code != 0:
        raise AnsibleFilterError("transpilation failed with return code %d: %s (%s)" % (return_code, out, err))

    return _decode(out.strip())


def _extract_asn(tags):
    asn = None
    for tag in tags:
        if tag.startswith('machine.metal-pod.io/network.primary.asn='):
            asn = tag.split('=')[1]
    
    return asn

def _generate_node_selectors(host):
    match_expression = dict()
    match_expression['key'] = 'kubernetes.io/hostname'
    match_expression['operator'] = 'In'
    match_expression['values'] = [host]
    
    node_selector = dict()
    node_selector['match-expressions'] = [match_expression]
    
    node_selectors = []
    node_selectors.append(node_selector)
    return node_selectors


def _extract_peer_address(host, k8s_nodes):
    for node in k8s_nodes:
        if node['metadata']['name'] == host:
            cidr = node['spec']['podCIDR']
            if PY2:
                cidr = unicode(cidr)
            
            net = ipaddress.ip_network(cidr)
            gen = net.hosts()
            return str(next(gen))
    raise AnsibleFilterError("could not find host in k8s nodes and determine peer address: %s", host)


def metal_lb_conf(hostnames, hostvars, cidrs, k8s_nodes):
    peers = []
    for host in hostnames: 
        host_vars = hostvars[host]
        if not host_vars:
            raise AnsibleFilterError("host has no hostvars: %s", host)

        if 'metal_tags' not in host_vars:
            raise AnsibleFilterError("host has no metal_tags: %s", host)

        if 'metal_hostname' not in host_vars:
            raise AnsibleFilterError("host has no metal_hostname: %s", host)

        asn = _extract_asn(host_vars['metal_tags'])
        if not asn:
            raise AnsibleFilterError("host has no asn specified in its metal_tags: %s", host)

        p = dict()
        p['peer-address'] = _extract_peer_address(host_vars['metal_hostname'], k8s_nodes)
        p['peer-asn'] = int(asn)
        p['my-asn'] = int(asn)
        p['node-selectors'] = _generate_node_selectors(host_vars['metal_hostname'])
        peers.append(p)
    
    address_pool = dict()
    address_pool['name'] = 'default'
    address_pool['protocol'] = 'bgp'
    address_pool['addresses'] = cidrs
    address_pools = [address_pool]

    return {
        'peers': peers,
        'address-pools': address_pools
    }
    

class FilterModule(object):
    '''Common cloud-native filter plugins'''

    def filters(self):
        return {
            'humanfriendly': parse_size,
            'transpile_ignition_config': transpile_ignition_config,
            'metal_lb_conf': metal_lb_conf,
        }
