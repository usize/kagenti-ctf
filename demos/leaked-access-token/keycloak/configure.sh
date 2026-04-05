#!/usr/bin/env bash
# Configure Keycloak for the leaked-access-token CTF demo
#
# Creates:
#   - Realm "ctf" (or uses existing)
#   - User "alex" with password "alex123", groups: engineering, hr
#   - Group mapper to include groups in JWT "groups" claim
#   - Client scope "document-service-aud" with audience mapper
#   - Enables token exchange
#
# Usage: ./configure.sh
#
# Prerequisites:
#   - Keycloak running at http://keycloak.localtest.me:8080
#   - Admin credentials: admin/admin
set -euo pipefail

KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak.localtest.me:8080}"
ADMIN_USER="${KEYCLOAK_ADMIN_USER:-admin}"
ADMIN_PASS="${KEYCLOAK_ADMIN_PASSWORD:-admin}"
REALM="ctf"

echo "==> Configuring Keycloak at ${KEYCLOAK_URL}"

# Get admin token
get_admin_token() {
    curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${ADMIN_USER}" \
        -d "password=${ADMIN_PASS}" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" | jq -r '.access_token'
}

TOKEN=$(get_admin_token)
if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to get admin token from Keycloak"
    exit 1
fi

AUTH="Authorization: Bearer ${TOKEN}"

# Helper: check if realm exists
realm_exists() {
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "${AUTH}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}")
    [ "$status" = "200" ]
}

# Create realm if it doesn't exist
if realm_exists; then
    echo "    Realm '${REALM}' already exists"
else
    echo "    Creating realm '${REALM}'..."
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms" \
        -H "${AUTH}" \
        -H "Content-Type: application/json" \
        -d "{
            \"realm\": \"${REALM}\",
            \"enabled\": true,
            \"accessTokenLifespan\": 300,
            \"ssoSessionMaxLifespan\": 1800,
            \"registrationAllowed\": false
        }"
    echo "    Realm created."
fi

# Refresh token (realm creation may take a moment)
TOKEN=$(get_admin_token)
AUTH="Authorization: Bearer ${TOKEN}"

# Create groups
echo "==> Creating groups..."
for GROUP in engineering hr; do
    EXISTS=$(curl -s -H "${AUTH}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/groups?search=${GROUP}" | jq -r '.[0].name // empty')
    if [ "${EXISTS}" = "${GROUP}" ]; then
        echo "    Group '${GROUP}' already exists"
    else
        curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/groups" \
            -H "${AUTH}" \
            -H "Content-Type: application/json" \
            -d "{\"name\": \"${GROUP}\"}"
        echo "    Created group '${GROUP}'"
    fi
done

# Create user "alex"
echo "==> Creating user 'alex'..."
ALEX_ID=$(curl -s -H "${AUTH}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=alex" | jq -r '.[0].id // empty')

if [ -n "${ALEX_ID}" ]; then
    echo "    User 'alex' already exists (id: ${ALEX_ID})"
else
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/users" \
        -H "${AUTH}" \
        -H "Content-Type: application/json" \
        -d '{
            "username": "alex",
            "enabled": true,
            "emailVerified": true,
            "firstName": "Alex",
            "lastName": "Engineer",
            "email": "alex@meridian.corp",
            "credentials": [{
                "type": "password",
                "value": "alex123",
                "temporary": false
            }]
        }'
    ALEX_ID=$(curl -s -H "${AUTH}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=alex" | jq -r '.[0].id')
    echo "    Created user 'alex' (id: ${ALEX_ID})"
fi

# Add alex to groups
echo "==> Adding alex to groups..."
for GROUP in engineering hr; do
    GROUP_ID=$(curl -s -H "${AUTH}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/groups?search=${GROUP}" | jq -r '.[0].id')
    if [ -n "${GROUP_ID}" ] && [ "${GROUP_ID}" != "null" ]; then
        curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/users/${ALEX_ID}/groups/${GROUP_ID}" \
            -H "${AUTH}" \
            -H "Content-Type: application/json"
        echo "    Added alex to '${GROUP}'"
    fi
done

# Create a client scope for groups claim in tokens
echo "==> Creating group mapper..."

# Check if groups scope already exists
GROUPS_SCOPE_ID=$(curl -s -H "${AUTH}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes" | jq -r '.[] | select(.name == "groups") | .id // empty')

if [ -n "${GROUPS_SCOPE_ID}" ]; then
    echo "    Client scope 'groups' already exists"
else
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes" \
        -H "${AUTH}" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "groups",
            "protocol": "openid-connect",
            "attributes": {
                "include.in.token.scope": "true",
                "display.on.consent.screen": "false"
            },
            "protocolMappers": [{
                "name": "groups",
                "protocol": "openid-connect",
                "protocolMapper": "oidc-group-membership-mapper",
                "consentRequired": false,
                "config": {
                    "full.path": "false",
                    "id.token.claim": "true",
                    "access.token.claim": "true",
                    "claim.name": "groups",
                    "userinfo.token.claim": "true"
                }
            }]
        }'
    GROUPS_SCOPE_ID=$(curl -s -H "${AUTH}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes" | jq -r '.[] | select(.name == "groups") | .id')
    echo "    Created client scope 'groups' (id: ${GROUPS_SCOPE_ID})"
fi

# Add groups scope as default realm scope
echo "    Adding 'groups' as default realm scope..."
curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/default-default-client-scopes/${GROUPS_SCOPE_ID}" \
    -H "${AUTH}" \
    -H "Content-Type: application/json" 2>/dev/null || true

# Create document-service-aud client scope (audience mapper)
echo "==> Creating document-service-aud client scope..."
DS_SCOPE_ID=$(curl -s -H "${AUTH}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes" | jq -r '.[] | select(.name == "document-service-aud") | .id // empty')

if [ -n "${DS_SCOPE_ID}" ]; then
    echo "    Client scope 'document-service-aud' already exists"
else
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes" \
        -H "${AUTH}" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "document-service-aud",
            "protocol": "openid-connect",
            "attributes": {
                "include.in.token.scope": "true",
                "display.on.consent.screen": "false"
            },
            "protocolMappers": [{
                "name": "document-service-audience",
                "protocol": "openid-connect",
                "protocolMapper": "oidc-audience-mapper",
                "consentRequired": false,
                "config": {
                    "included.custom.audience": "document-service",
                    "id.token.claim": "false",
                    "access.token.claim": "true"
                }
            }]
        }'
    DS_SCOPE_ID=$(curl -s -H "${AUTH}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes" | jq -r '.[] | select(.name == "document-service-aud") | .id')
    echo "    Created client scope 'document-service-aud' (id: ${DS_SCOPE_ID})"
fi

# Create document-service client (resource server / audience target)
# Keycloak's token exchange requires the target audience to exist as a client.
echo "==> Creating 'document-service' client (bearer-only)..."
DS_CLIENT_ID=$(curl -s -H "${AUTH}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" | jq -r '.[] | select(.clientId == "document-service") | .id // empty')

if [ -n "${DS_CLIENT_ID}" ]; then
    echo "    Client 'document-service' already exists"
else
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
        -H "${AUTH}" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "document-service",
            "enabled": true,
            "publicClient": false,
            "bearerOnly": true,
            "serviceAccountsEnabled": false,
            "standardFlowEnabled": false,
            "directAccessGrantsEnabled": false,
            "attributes": {
                "standard.token.exchange.enabled": "true"
            }
        }'
    echo "    Created client 'document-service'"
fi

# Create a public client for getting Alex's token (for the demo)
echo "==> Creating 'ctf-demo-cli' client..."
CLI_ID=$(curl -s -H "${AUTH}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" | jq -r '.[] | select(.clientId == "ctf-demo-cli") | .id // empty')

if [ -n "${CLI_ID}" ]; then
    echo "    Client 'ctf-demo-cli' already exists"
else
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
        -H "${AUTH}" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "ctf-demo-cli",
            "enabled": true,
            "publicClient": true,
            "directAccessGrantsEnabled": true,
            "standardFlowEnabled": false,
            "serviceAccountsEnabled": false,
            "attributes": {
                "standard.token.exchange.enabled": "true"
            }
        }'
    CLI_ID=$(curl -s -H "${AUTH}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" | jq -r '.[] | select(.clientId == "ctf-demo-cli") | .id')
    echo "    Created client 'ctf-demo-cli' (id: ${CLI_ID})"
fi

# Add document-service-aud and groups as default client scopes for ctf-demo-cli
if [ -n "${DS_SCOPE_ID}" ] && [ -n "${CLI_ID}" ]; then
    curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${CLI_ID}/default-client-scopes/${DS_SCOPE_ID}" \
        -H "${AUTH}" 2>/dev/null || true
    echo "    Assigned 'document-service-aud' scope to ctf-demo-cli"
fi

if [ -n "${GROUPS_SCOPE_ID}" ] && [ -n "${CLI_ID}" ]; then
    curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${CLI_ID}/default-client-scopes/${GROUPS_SCOPE_ID}" \
        -H "${AUTH}" 2>/dev/null || true
    echo "    Assigned 'groups' scope to ctf-demo-cli"
fi

# Assign Claude's auto-registered audience scope to ctf-demo-cli
# This must run AFTER the Claude agent pod deploys (client-registration creates
# Claude's Keycloak client and its audience scope). Keycloak token exchange
# requires the requesting client (Claude) to be in the subject token's audience.
echo "==> Assigning Claude's audience scope to ctf-demo-cli..."

# Refresh token
TOKEN=$(get_admin_token)
AUTH="Authorization: Bearer ${TOKEN}"

# Find Claude's audience scope (created by client-registration sidecar)
CLAUDE_AUD_ID=$(curl -s -H "${AUTH}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes" | jq -r '.[] | select(.name | test("^agent-ctf-claude")) | .id // empty')

if [ -n "${CLAUDE_AUD_ID}" ]; then
    # Re-fetch CLI_ID in case it wasn't set
    CLI_ID=$(curl -s -H "${AUTH}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" | jq -r '.[] | select(.clientId == "ctf-demo-cli") | .id')
    curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${CLI_ID}/default-client-scopes/${CLAUDE_AUD_ID}" \
        -H "${AUTH}" 2>/dev/null || true
    echo "    Assigned Claude's audience scope to ctf-demo-cli"

    # Also add document-service-aud as optional scope on Claude's client
    CLAUDE_CLIENT_ID=$(curl -s -H "${AUTH}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" | jq -r '.[] | select(.clientId | test("spiffe.*ctf-claude")) | .id // empty')
    if [ -n "${CLAUDE_CLIENT_ID}" ] && [ -n "${DS_SCOPE_ID}" ]; then
        curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${CLAUDE_CLIENT_ID}/optional-client-scopes/${DS_SCOPE_ID}" \
            -H "${AUTH}" 2>/dev/null || true
        echo "    Assigned 'document-service-aud' as optional scope on Claude's client"
    fi
else
    echo "    Claude's audience scope not found yet."
    echo "    Run this script again after the Claude agent pod is deployed."
fi

echo ""
echo "==> Keycloak configuration complete!"
echo ""
echo "    Realm:    ${REALM}"
echo "    User:     alex / alex123"
echo "    Groups:   engineering, hr"
echo "    Clients:  ctf-demo-cli (public), document-service (bearer-only)"
echo "    Scopes:   groups, document-service-aud"
echo ""
echo "    Token URL: ${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token"
