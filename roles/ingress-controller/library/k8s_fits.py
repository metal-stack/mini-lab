#!/usr/bin/python
# -*- coding: utf-8 -*-

# (c) 2018, Chris Houseknecht <@chouseknecht>
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import absolute_import, division, print_function

__metaclass__ = type


"""
This is basically the original K8s module, but additionally provides setting a proxy.

FIXME Can possibly be removed in Ansible 2.9 if this merge requests goes through:
https://github.com/ansible/ansible/pull/55377
"""


import copy
from mock import patch, PropertyMock

from ansible.module_utils.k8s.raw import KubernetesRawModule
from ansible.module_utils.k8s.common import AUTH_ARG_SPEC, COMMON_ARG_SPEC


def validate_spec():
    return dict(
        fail_on_error=dict(type='bool'),
        version=dict(),
        strict=dict(type='bool', default=True)
    )


def condition_spec():
    return dict(
        type=dict(),
        status=dict(default=True, choices=[True, False, "Unknown"]),
        reason=dict()
    )


def patched_argspec():
    AUTH_ARG_SPEC.update(dict(proxy=dict()))
    argument_spec = copy.deepcopy(COMMON_ARG_SPEC)
    argument_spec.update(copy.deepcopy(AUTH_ARG_SPEC))
    argument_spec['merge_type'] = dict(type='list', choices=['json', 'merge', 'strategic-merge'])
    argument_spec['wait'] = dict(type='bool', default=False)
    argument_spec['wait_timeout'] = dict(type='int', default=120)
    argument_spec['wait_condition'] = dict(type='dict', default=None, options=condition_spec)
    argument_spec['validate'] = dict(type='dict', default=None, options=validate_spec)
    argument_spec['append_hash'] = dict(type='bool', default=False)
    return argument_spec


def main():
    with patch("ansible.module_utils.k8s.raw.KubernetesRawModule.argspec", new_callable=PropertyMock) as mock:
        mock.return_value = patched_argspec()
        KubernetesRawModule().execute_module()


if __name__ == '__main__':
    main()
