Role Name
=========

A brief description of the role goes here.

## Notes

Well known config for the apiserver
# http://localhost:3001/oidc/.well-known/openid-configuration


Machine2Machine Account
https://docs.logto.io/integrate-logto/interact-with-management-api

```bash
curl --location \
  --request POST 'http://logto.172.17.0.1.nip.io:8080' \
  --header 'Authorization: Basic a3FxNm5tWmpRdVZkQzJPOHpWOUozR2dqRnF2Y09aWUEK' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode 'resource=https://default.logto.app/api' \
  --data-urlencode 'scope=all'
```

Does not work yet

Requirements
------------

Any pre-requisites that may not be covered by Ansible itself or the role should be mentioned here. For instance, if the role uses the EC2 module, it may be a good idea to mention in this section that the boto package is required.

Role Variables
--------------

A description of the settable variables for this role should go here, including any variables that are in defaults/main.yml, vars/main.yml, and any variables that can/should be set via parameters to the role. Any variables that are read from other roles and/or the global scope (ie. hostvars, group vars, etc.) should be mentioned here as well.

Dependencies
------------

A list of other roles hosted on Galaxy should go here, plus any details in regards to parameters that may need to be set for other roles, or variables that are used from other roles.

Example Playbook
----------------

Including an example of how to use your role (for instance, with variables passed in as parameters) is always nice for users too:

    - hosts: servers
      roles:
         - { role: username.rolename, x: 42 }

License
-------

MIT

Author Information
------------------

An optional section for the role authors to include contact information, or a website (HTML is not allowed).
