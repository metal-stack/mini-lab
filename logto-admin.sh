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

# ===============================
# 3. (Optional) Liste bestehende Third-Party-Apps
# ===============================
echo "📜 Bestehende Third-Party-Anwendungen:"
curl -s --location \
  --request GET "$LOGTO_API_URL/api/applications?isThirdParty=true" \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  | jq '.[] | {id, name, description}'

# ===============================
# 4. Erstelle mini-lab Anwendung
# ===============================
echo "🚀 Erstelle neue Anwendung: $APP_NAME ..."
CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" --location \
  --request POST "$LOGTO_API_URL/api/applications" \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  --header "Content-Type: application/json" \
  --data "{
    \"name\": \"$APP_NAME\",
    \"description\": \"$APP_DESCRIPTION\",
    \"type\": \"Traditional\",
    \"oidcClientMetadata\": {
      \"redirectUris\": [\"$REDIRECT_URI\"],
      \"postLogoutRedirectUris\": [\"$REDIRECT_URI\"]
    },
    \"isThirdParty\": true
  }")

HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)
BODY=$(echo "$CREATE_RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
  echo "❌ Fehler beim Erstellen der Anwendung (HTTP $HTTP_CODE):"
  echo "$BODY" | jq .
  exit 1
fi

echo "✅ Anwendung erfolgreich erstellt:"
echo "$BODY" | jq .
