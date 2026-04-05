#!/usr/bin/env bash
# Generate an access token for user Alex from Keycloak
#
# Outputs the raw JWT access token to stdout.
# If --verbose is passed, also prints decoded token claims to stderr.
#
# Usage:
#   TOKEN=$(./scripts/generate-token.sh)
#   ./scripts/generate-token.sh --verbose
set -euo pipefail

KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak.localtest.me:8080}"
REALM="${KEYCLOAK_REALM:-ctf}"
CLIENT_ID="ctf-demo-cli"
USERNAME="alex"
PASSWORD="alex123"
VERBOSE=false

if [ "${1:-}" = "--verbose" ]; then
    VERBOSE=true
fi

# Get token via direct access grant (resource owner password)
RESPONSE=$(curl -s -X POST \
    "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=${CLIENT_ID}" \
    -d "username=${USERNAME}" \
    -d "password=${PASSWORD}" \
    -d "scope=openid groups document-service-aud")

TOKEN=$(echo "${RESPONSE}" | jq -r '.access_token')

if [ "${TOKEN}" = "null" ] || [ -z "${TOKEN}" ]; then
    echo "ERROR: Failed to get token from Keycloak" >&2
    echo "${RESPONSE}" | jq . >&2
    exit 1
fi

if [ "${VERBOSE}" = true ]; then
    echo "==> Token obtained for user '${USERNAME}'" >&2
    echo "" >&2
    echo "==> Decoded claims:" >&2
    echo "${TOKEN}" | cut -d. -f2 | tr '_-' '/+' | awk '{len=length($0); pad=len%4; if(pad) for(i=0;i<4-pad;i++) $0=$0"="; print}' | base64 -d 2>/dev/null | jq . >&2
    echo "" >&2
fi

echo "${TOKEN}"
