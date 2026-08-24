#!/usr/bin/env bash
# S-21 delegation-drift probe.
#
# Runs on davbuntu (cron, every 30 min). Fetches the two Matrix well-known
# files served for davlin.io and compares them against the values this repo
# expects (infra/wellknown-worker/src/index.js is the source of truth — if
# TARGET changes there on failover, update EXPECTED_* below and re-copy this
# file to davbuntu).
#
# On a mismatch OR a fetch failure, the probe appends to drift-alerts.log
# and sends a push via ntfy.sh.
#
# STATUS as of S-21: logic tested standalone in both pass and
# --dry-run-fail mode (real ntfy.sh push confirmed in fail mode). NOT yet
# installed into davbuntu cron — see RESTORE-NOTES.md "Blocker B" (its
# log path lives under /srv/synapse-standby, which does not exist yet).
#
# Usage:
#   drift-probe.sh                 normal run
#   drift-probe.sh --dry-run-fail  compare against a deliberately wrong
#                                   expected value, to test the alert path
#                                   without touching prod well-known files.

set -uo pipefail

SERVER_URL="https://davlin.io/.well-known/matrix/server"
CLIENT_URL="https://davlin.io/.well-known/matrix/client"

# Expected values (must match infra/wellknown-worker/src/index.js TARGET).
# Update this on every failover/migration.
EXPECTED_SERVER='{"m.server":"davlin-matrix.exe.xyz:443"}'
EXPECTED_CLIENT='{"m.homeserver":{"base_url":"https://davlin-matrix.exe.xyz"}}'

# ntfy.sh topic for drift alerts. Random suffix generated once at S-21
# authoring time so the topic isn't guessable; record any change here.
NTFY_TOPIC="davlin-matrix-drift-fce26c1e"

LOG_DIR="/srv/synapse-standby"
ALERT_LOG="${LOG_DIR}/drift-alerts.log"

# Cloudflare returns 403 to generic/python UAs (verified during S-21). Use a
# realistic browser UA so the probe sees what a real client sees.
USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

DRY_RUN_FAIL=0
if [[ "${1:-}" == "--dry-run-fail" ]]; then
  DRY_RUN_FAIL=1
  EXPECTED_SERVER='{"m.server":"WRONG-TARGET.example:443"}'
fi

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

alert() {
  local reason="$1"
  mkdir -p "$LOG_DIR"
  printf '%s DRIFT: %s\n' "$(ts)" "$reason" >> "$ALERT_LOG"
  curl -fsS \
    -H "Title: davlin.io well-known drift" \
    -H "Priority: high" \
    -H "Tags: warning" \
    -d "$reason" \
    "https://ntfy.sh/${NTFY_TOPIC}" >/dev/null 2>&1
}

fetch() {
  local url="$1"
  curl -fsS --max-time 10 -A "$USER_AGENT" "$url" 2>/dev/null
}

server_body="$(fetch "$SERVER_URL")"
server_rc=$?
client_body="$(fetch "$CLIENT_URL")"
client_rc=$?

if [[ $server_rc -ne 0 ]]; then
  alert "fetch failed for $SERVER_URL (curl exit $server_rc)"
  exit 1
fi

if [[ $client_rc -ne 0 ]]; then
  alert "fetch failed for $CLIENT_URL (curl exit $client_rc)"
  exit 1
fi

if [[ "$server_body" != "$EXPECTED_SERVER" ]]; then
  alert "server well-known mismatch: got '${server_body}' expected '${EXPECTED_SERVER}'"
  exit 1
fi

if [[ "$client_body" != "$EXPECTED_CLIENT" ]]; then
  alert "client well-known mismatch: got '${client_body}' expected '${EXPECTED_CLIENT}'"
  exit 1
fi

if [[ $DRY_RUN_FAIL -eq 1 ]]; then
  # Should not reach here in dry-run-fail mode — the server mismatch above
  # must have already caught it and exited 1.
  echo "$(ts) dry-run-fail did not trigger an alert; probe logic is broken" >&2
  exit 2
fi

echo "$(ts) OK: well-known matches expected values"
exit 0
