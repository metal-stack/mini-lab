#!/usr/bin/env python

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import time
import json
from kubernetes import client, config
from kubernetes.client.rest import ApiException
from pprint import pprint
from ansible.module_utils.basic import AnsibleModule


def run_module():
    module_args = dict(
        name=dict(type='str', required=True),
        namespace=dict(type='str', required=True),
        kubeconfig=dict(type='raw', no_log=True, required=False),
        body=dict(type='dict', required=True)
    )

    result = dict(
        changed=False,
        result=''
    )

    module = AnsibleModule(
        argument_spec=module_args,
        supports_check_mode=True
    )

    if module.check_mode:
        module.exit_json(**result)

    kubeconfig = module.params.get('kubeconfig')

    if isinstance(kubeconfig, str) or kubeconfig is None:
        api_client = config.new_client_from_config(config_file=kubeconfig)
    elif isinstance(kubeconfig, dict):
        api_client = config.new_client_from_config_dict(config_dict=kubeconfig)
    else:
        module.fail_json(msg="Error while reading kubeconfig parameter - a string or dict expected, but got %s instead" % type(kubeconfig), **result)

    api_instance = client.CoreV1Api(api_client)

    name = module.params.get('name')
    namespace = module.params.get('namespace')
    body = module.params.get('body')

    try:
        api_response = api_instance.patch_namespaced_service_status(name, namespace, body)
        result['changed'] = True
        result['result'] = json.dumps(api_client.sanitize_for_serialization(api_response), sort_keys=True, indent=4)
    except ApiException as e:
        module.fail_json(msg="Exception when calling CoreV1Api->patch_namespaced_service_status: %s\n" % e, **result)

    module.exit_json(**result)


def main():
    run_module()


if __name__ == '__main__':
    main()
