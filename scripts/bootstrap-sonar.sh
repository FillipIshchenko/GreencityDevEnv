#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SONAR_URL="${SONAR_URL:-http://localhost:9000}"
DEFAULT_USER="admin"
DEFAULT_PASS="admin"
NEW_PASS="${SONAR_ADMIN_PASSWORD:-Admin12345!}"
JENKINS_WEBHOOK="${JENKINS_WEBHOOK:-http://jenkins:8080/sonarqube-webhook/}"
ENV_FILE=".env"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[sonar-setup]${NC} $*"; }
warn() { echo -e "${YELLOW}[sonar-setup]${NC} $*"; }
fail() { echo -e "${RED}[sonar-setup]${NC} $*" >&2; exit 1; }

info "Waiting for SonarQube at ${SONAR_URL} to be UP ..."
for i in $(seq 1 60); do
  status="$(curl -sf "${SONAR_URL}/api/system/status" | jq -r '.status' 2>/dev/null || echo '')"
  if [ "$status" = "UP" ]; then
    info "SonarQube reports UP."
    break
  fi
  sleep 5
  [ "$i" -eq 60 ] && fail "SonarQube did not become UP in time."
done

info "Waiting for the authentication API to respond ..."
for i in $(seq 1 24); do
  if curl -sf -u "${DEFAULT_USER}:${DEFAULT_PASS}" \
       "${SONAR_URL}/api/authentication/validate" >/dev/null 2>&1 \
     || curl -sf -u "${DEFAULT_USER}:${NEW_PASS}" \
       "${SONAR_URL}/api/authentication/validate" >/dev/null 2>&1; then
    info "Authentication API is ready."
    break
  fi
  sleep 5
  [ "$i" -eq 24 ] && warn "Auth API still not confirmed ready — continuing anyway, the change step will retry."
done
default_works() {
  curl -sf -u "${DEFAULT_USER}:${DEFAULT_PASS}" "${SONAR_URL}/api/authentication/validate" \
    | jq -e '.valid == true' >/dev/null 2>&1
}
newpass_works() {
  curl -sf -u "${DEFAULT_USER}:${NEW_PASS}" "${SONAR_URL}/api/authentication/validate" \
    | jq -e '.valid == true' >/dev/null 2>&1
}
if newpass_works; then
  warn "Admin password already set to the configured value — reusing it."
  AUTH="${DEFAULT_USER}:${NEW_PASS}"
elif default_works; then
  info "Changing default admin password ..."
  changed=0
  for attempt in $(seq 1 12); do
    code="$(curl -s -o /dev/null -w '%{http_code}' \
      -u "${DEFAULT_USER}:${DEFAULT_PASS}" -X POST \
      "${SONAR_URL}/api/users/change_password" \
      --data-urlencode "login=${DEFAULT_USER}" \
      --data-urlencode "previousPassword=${DEFAULT_PASS}" \
      --data-urlencode "password=${NEW_PASS}")"
    if newpass_works; then
      changed=1
      break
    fi
    warn "Password change not effective yet (HTTP ${code}); Sonar still settling, retry ${attempt}/12 ..."
    sleep 5
  done
  if [ "$changed" -ne 1 ]; then
    fail "Failed to change the admin password after several attempts. Sonar may still be initialising — wait a minute and re-run this script."
  fi
  info "Admin password changed and verified."
  AUTH="${DEFAULT_USER}:${NEW_PASS}"
else
  fail "Cannot authenticate to Sonar with default OR configured password. If you changed the admin password manually, set SONAR_ADMIN_PASSWORD to it and re-run."
fi

TOKEN_NAME="jenkins-token"
info "Generating analysis token '${TOKEN_NAME}' ..."
curl -sf -u "$AUTH" -X POST "${SONAR_URL}/api/user_tokens/revoke" \
  --data-urlencode "name=${TOKEN_NAME}" >/dev/null 2>&1 || true
TOKEN="$(curl -sf -u "$AUTH" -X POST "${SONAR_URL}/api/user_tokens/generate" \
  --data-urlencode "name=${TOKEN_NAME}" | jq -r '.token')"
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || fail "Failed to generate Sonar token."
info "Registering Jenkins webhook ..."
existing="$(curl -sf -u "$AUTH" "${SONAR_URL}/api/webhooks/list" \
  | jq -r '.webhooks[]? | select(.name=="jenkins") | .key' 2>/dev/null || echo '')"
if [ -n "$existing" ]; then
  curl -sf -u "$AUTH" -X POST "${SONAR_URL}/api/webhooks/delete" \
    --data-urlencode "webhook=${existing}" >/dev/null 2>&1 || true
fi
curl -sf -u "$AUTH" -X POST "${SONAR_URL}/api/webhooks/create" \
  --data-urlencode "name=jenkins" \
  --data-urlencode "url=${JENKINS_WEBHOOK}" >/dev/null \
  && info "Webhook -> ${JENKINS_WEBHOOK}"
touch "$ENV_FILE"
if grep -q '^SONAR_TOKEN=' "$ENV_FILE"; then
  sed -i.bak "s|^SONAR_TOKEN=.*|SONAR_TOKEN=${TOKEN}|" "$ENV_FILE" && rm -f "${ENV_FILE}.bak"
else
  echo "SONAR_TOKEN=${TOKEN}" >> "$ENV_FILE"
fi

info "Done. SONAR_TOKEN written to ${ENV_FILE}."
warn "Jenkins must be (re)started after this so JCasC reads the new token:"
warn "    docker compose up -d --force-recreate jenkins"
