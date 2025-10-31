#!/bin/bash
set -euo pipefail

# ===============================
# Konfiguration
# ===============================
LOGTO_DB_CONTAINER="logto-postgres-1"
LOGTO_DB_USER="postgres"
LOGTO_DB_NAME="logto"
LOGTO_API_URL="http://localhost:3002"
CLIENT_ID="m-admin"
RESOURCE="https://admin.logto.app/api"
SCOPE="all"

APP_NAME="mini-lab"
APP_DESCRIPTION="mini-lab IdP"
REDIRECT_URI="http://v2.api.172.17.0.1.nip.io:8080/auth/oidc/callback"

ADMIN_NAME="admin"
ADMIN_PW="password1234"

# ===============================
# 1. Hole m-admin secret aus der Datenbank
# ===============================
echo "🔑 Hole Client Secret für ${CLIENT_ID}..."
CLIENT_SECRET=$(docker exec -it "$LOGTO_DB_CONTAINER" sh -c \
  "psql -U $LOGTO_DB_USER -d $LOGTO_DB_NAME -t -A -c \"SELECT secret FROM applications WHERE id = '$CLIENT_ID';\"" \
  | tr -d '\r')
if [[ -z "$CLIENT_SECRET" ]]; then
  echo "❌ Konnte Client Secret nicht finden. Bitte prüfe, ob die Datenbank läuft und m-admin existiert."
  exit 1
fi
echo "✅ Secret gefunden: ${CLIENT_SECRET}"

# ===============================
# 2. Hole Access Token
# ===============================
echo "🔐 Fordere Access Token an..."
ACCESS_TOKEN=$(curl -s --location \
  --request POST "$LOGTO_API_URL/oidc/token" \
  --header "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode "client_secret=$CLIENT_SECRET" \
  --data-urlencode "resource=$RESOURCE" \
  --data-urlencode "scope=$SCOPE" \
  | jq -r '.access_token')
if [[ "$ACCESS_TOKEN" == "null" || -z "$ACCESS_TOKEN" ]]; then
  echo "❌ Fehler beim Abrufen des Access Tokens."
  exit 1
fi
echo "✅ Access Token erfolgreich erhalten."

# Create admin-user
echo "👤 Erstelle Admin-Benutzer..."
CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" --location \
  --request POST "$LOGTO_API_URL/api/users" \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  --header "Content-Type: application/json" \
  --data "{
    \"username\": \"$ADMIN_NAME\",
    \"password\": \"$ADMIN_PW\"
  }")
HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)
BODY=$(echo "$CREATE_RESPONSE" | sed '$d')
if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
  echo "❌ Fehler beim Erstellen des Adminusers (HTTP $HTTP_CODE):"
  echo "$BODY" | jq .
  exit 1
fi
echo "✅ Adminuser erfolgreich erstellt:"
echo "$BODY" | jq .
USERID=$(echo "$BODY" | jq -r '.id')

# Create admin-user
echo "Add user to organisation"
CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" --location \
  --request POST "$LOGTO_API_URL/api/organizations/t-default/users" \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  --header "Content-Type: application/json" \
  --data "{
    \"userIds\": [\"$USERID\"]
  }")
HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)
BODY=$(echo "$CREATE_RESPONSE" | sed '$d')
if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
  echo "❌ Fehler beim Hinzufügen des Adminusers zur Organisation (HTTP $HTTP_CODE):"
  echo "$BODY" | jq .
  exit 1
fi
echo "✅ Adminuser erfolgreich hinzugefügt:"


echo "Adminrechte der Organisation zugeweisen"
CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" --location \
  --request POST "$LOGTO_API_URL/api/organizations/t-default/users/roles" \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  --header "Content-Type: application/json" \
  --data "{
    \"userIds\": [\"$USERID\"],
    \"organizationRoleIds\": [\"admin\"]
  }")
HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)
BODY=$(echo "$CREATE_RESPONSE" | sed '$d')
if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
  echo "❌ Fehler beim Hinzufügen der Adminrechte zur Organisation (HTTP $HTTP_CODE):"
  echo "$BODY" | jq .
  exit 1
fi
echo "✅ Adminrechte erfolgreich hinzugefügt:"

echo "Rollen laden"
CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" --location \
  --request GET "$LOGTO_API_URL/api/roles?type=User" \
  --header "Authorization: Bearer $ACCESS_TOKEN")
HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)
BODY=$(echo "$CREATE_RESPONSE" | sed '$d')
if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
  echo "❌ Fehler beim Laden der Rollen (HTTP $HTTP_CODE):"
  echo "$BODY" | jq .
  exit 1
fi
echo "✅ Rollen erfolgreich geladen:"
echo "$BODY" | jq .
ROLE_IDS=$(echo "$BODY" | jq -r '.[].id' | jq -R . | paste -sd, -)
echo "Gefundene Rollen IDs: $ROLE_IDS"

echo "Rollen zu Adminuser zuweisen"
CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" --location \
  --request POST "$LOGTO_API_URL/api/users/$USERID/roles" \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  --header "Content-Type: application/json" \
  --data "{
    \"roleIds\": [$(echo "$ROLE_IDS" | paste -sd, -)]
  }")
HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)
BODY=$(echo "$CREATE_RESPONSE" | sed '$d')
if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
  echo "❌ Fehler beim Zuweisen der Rollen (HTTP $HTTP_CODE):"
  echo "$BODY" | jq .
  exit 1
fi
echo "✅ Rollen erfolgreich zugewiesen:"

echo "Login anpassen"
CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" --location \
  --request PATCH "$LOGTO_API_URL/api/sign-in-exp" \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  --header "Content-Type: application/json" \
  --data "{
    \"tenantId\": \"admin\",
    \"signInMode\": \"SignIn\"
  }")
HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)
BODY=$(echo "$CREATE_RESPONSE" | sed '$d')
if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
  echo "❌ Fehler beim Anpassen des Logins (HTTP $HTTP_CODE):"
  echo "$BODY" | jq .
  exit 1
fi
echo "✅ Login erfolgreich angepasst:"