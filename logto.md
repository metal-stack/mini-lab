curl --location \
  --request POST 'http://localhost:3001/oidc/token' \
  --header 'Authorization: Basic MHN4ZTd3NWV1eGdqcDFrZnJid3g3OlVueVp3d0RCY2gzUjA1NTRzcUJRR0VuSWVjU0hyMXk5' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode 'resource=https://default.logto.app/api' \
  --data-urlencode 'scope=all'

-------

RFtlQNmRxH4HLDMZVra6Zad0VeWNsT8a

curl --location \
  --request POST 'http://localhost:3002/oidc/token' \
  --header 'Authorization: Basic bS1hZG1pbjpSRnRsUU5tUnhINEhMRE1aVnJhNlphZDBWZVdOc1Q4YQ' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode 'resource=https://default.logto.app/api' \
  --data-urlencode 'scope=all'

curl \
 --request POST 'http://localhost:3001/api/applications' \
 --header "Authorization: Bearer RFtlQNmRxH4HLDMZVra6Zad0VeWNsT8a" \
 --header "Content-Type: application/json" \
 --data '{"name":"mini-lab","description":"Mini-Lab","type":"MachineToMachine"}'


----

./logto-create-admin --baseUrl=http://localhost:3002 --appSecret=RFtlQNmRxH4HLDMZVra6Zad0VeWNsT8a --username=admin --password=password123

----

Solution:

1. Get m-admin token
docker exec -it logto-postgres-1 sh -c 'psql -U postgres -d logto -t -A -c "SELECT secret FROM applications WHERE id = '\''m-admin'\'';"'

2. Use the token to get access token for m-admin
curl --location \
  --request POST 'http://localhost:3002/oidc/token' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode 'client_id=m-admin' \
  --data-urlencode 'client_secret=RFtlQNmRxH4HLDMZVra6Zad0VeWNsT8a' \
  --data-urlencode 'resource=https://admin.logto.app/api' \
  --data-urlencode 'scope=all' \
| jq -r '.access_token'

3. Use the access token to manage entities
curl --location \
  --request GET 'http://localhost:3002/api/applications?isThirdParty=true' \
  --header 'Authorization: Bearer eyJhbGciOiJFUzM4NCIsInR5cCI6ImF0K2p3dCIsImtpZCI6IjlobWw4NDl5NUZYQk5mUE93bnA1Q1g3ZUVkdERTejl5ejd5SllOZ0RnajAifQ.eyJqdGkiOiI5aFZDZWlaV202Q1p4Z0VDRTJWVDIiLCJzdWIiOiJtLWFkbWluIiwiaWF0IjoxNzYxNzQ0NjA1LCJleHAiOjE3NjE3NDgyMDUsInNjb3BlIjoiYWxsIiwiY2xpZW50X2lkIjoibS1hZG1pbiIsImlzcyI6Imh0dHA6Ly9sb2NhbGhvc3Q6MzAwMi9vaWRjIiwiYXVkIjoiaHR0cHM6Ly9hZG1pbi5sb2d0by5hcHAvYXBpIn0.u7GEcRma56PDiFSPF4_281xtodMUD1ZlpQu_NNAWKhpAj5RAg_zZKFk7sR3euXk3mgPqjko2oPBBTbDh9i0hiwjRDY-Iv_pYDlD9L18xUbjjIyoPI6X3hqTGNXpK-u0t'

4. Create mini-lab oidc app
curl --location \
  --request POST 'http://localhost:3002/api/applications' \
  --header 'Authorization: Bearer eyJhbGciOiJFUzM4NCIsInR5cCI6ImF0K2p3dCIsImtpZCI6IjlobWw4NDl5NUZYQk5mUE93bnA1Q1g3ZUVkdERTejl5ejd5SllOZ0RnajAifQ.eyJqdGkiOiI5aFZDZWlaV202Q1p4Z0VDRTJWVDIiLCJzdWIiOiJtLWFkbWluIiwiaWF0IjoxNzYxNzQ0NjA1LCJleHAiOjE3NjE3NDgyMDUsInNjb3BlIjoiYWxsIiwiY2xpZW50X2lkIjoibS1hZG1pbiIsImlzcyI6Imh0dHA6Ly9sb2NhbGhvc3Q6MzAwMi9vaWRjIiwiYXVkIjoiaHR0cHM6Ly9hZG1pbi5sb2d0by5hcHAvYXBpIn0.u7GEcRma56PDiFSPF4_281xtodMUD1ZlpQu_NNAWKhpAj5RAg_zZKFk7sR3euXk3mgPqjko2oPBBTbDh9i0hiwjRDY-Iv_pYDlD9L18xUbjjIyoPI6X3hqTGNXpK-u0t' \
  --header 'Content-Type: application/json' \
  --data '{
    "name": "mini-lab",
    "description": "mini-lab IdP",
    "type": "Traditional",
    "oidcClientMetadata": {
      "redirectUris": [
        "http://v2.api.172.17.0.1.nip.io:8080/auth/oidc/callback"
      ],
      "postLogoutRedirectUris": [
        "http://v2.api.172.17.0.1.nip.io:8080/auth/oidc/callback"
      ]
    },
    "isThirdParty": true
  }'
