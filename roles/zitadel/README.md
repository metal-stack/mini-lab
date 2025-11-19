# Zitadel

Role that deploys and manages and configures Zitadel, an open-source identity and access management system. Here you can find the project: [Zitadel](https://zitadel.com/)

## UI

Because `ExternalSecure: true` is set by default, Zitadel will be available over HTTPS. We may need to change this to `false` if we want to use HTTP.

UI will be available at `https://zitadel.172.17.0.1.nip.io:4443`.

Admin:
- Username: `admin@metalstack.zitadel.172.17.0.1.nip.io`
- Password: `Password1!`


## Problems
- login image not loading because of csp