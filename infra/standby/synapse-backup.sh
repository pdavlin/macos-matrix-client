#!/usr/bin/env bash
# S-21 standing backup pipeline. Runs on davbuntu (cron, nightly).
#
# STATUS: both S-21 blockers are now clear. Blocker A was resolved by S-23
# (transport moved to the tailnet, 2026-08-30) and Blocker B by the davbuntu
# bootstrap (2026-08-30). Not yet installed into cron.
#
# Pulls three things from the primary over Tailscale SSH (see
# infra/standby/vm-dispatch.sh and infra/tailnet/README.md for the VM-side
# setup and the tailnet policy):
#
#   (a) a pg_dump of the synapse Postgres database
#   (b) an rsync of the media store
#   (c) a copy of homeserver.yaml, conf.d/, and the signing key
#
# Layout on davbuntu:
#   /srv/synapse-standby/dumps/synapse-YYYY-MM-DD.dump
#   /srv/synapse-standby/media/            (rsync mirror, not dated)
#   /srv/synapse-standby/config/YYYY-MM-DD/
#
# Dumps and dated config snapshots older than RETENTION_DAYS are pruned.
# Everything is logged to /srv/synapse-standby/backup.log.

set -uo pipefail

# The tailnet name, NOT davlin-matrix.exe.xyz. exe.dev's SSH gateway owns
# auth for the .exe.xyz name and never reaches this account; it is also the
# path that failed in bursts roughly eight times over 2026-08-29/30. Tailscale
# SSH intercepts port 22 for the tailnet name, so no key and no -i are needed:
# authentication is the tailnet identity, authorised by the ACL rule that
# admits pdavlin@github to tag:matrix-hs as synbackup.
VM_HOST="davlin-matrix"
VM_USER="synbackup"

ROOT="/srv/synapse-standby"
DUMP_DIR="${ROOT}/dumps"
MEDIA_DIR="${ROOT}/media"
CONFIG_DIR="${ROOT}/config"
LOG_FILE="${ROOT}/backup.log"

RETENTION_DAYS=14
DATE="$(date -u '+%Y-%m-%d')"

# Plain ssh, not `tailscale ssh`. The wrapper rejects the `-l <user>` that
# rsync passes to its -e transport, so rsync cannot use it. Plain ssh works
# for both because Tailscale SSH intercepts :22 on the tailnet name.
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15)

mkdir -p "$DUMP_DIR" "$MEDIA_DIR" "$CONFIG_DIR"

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" | tee -a "$LOG_FILE"
}

# ntfy.sh topic, shared with drift-probe.sh. Keep the two in step: if one
# changes, change both, or half the alerts go to a topic nobody watches.
NTFY_TOPIC="davlin-matrix-drift-fce26c1e"

# A nightly backup that fails quietly is worse than no backup, because it
# looks like it is working until a restore is attempted. Logging to a file
# nobody reads is quiet. cron's own mail goes nowhere on a headless box
# without an MTA, so failure has to push the same way the drift probe does.
fail() {
  log "ERROR: $1"
  curl -fsS \
    -H "Title: davlin.io standby backup FAILED" \
    -H "Priority: high" \
    -H "Tags: rotating_light" \
    -d "$(hostname): $1" \
    "https://ntfy.sh/${NTFY_TOPIC}" >/dev/null 2>&1
  exit 1
}

log "=== backup run start ==="

# (a) pg_dump, custom format, streamed straight to a dated file.
DUMP_FILE="${DUMP_DIR}/synapse-${DATE}.dump"
log "pg_dump -> ${DUMP_FILE}"
if ssh "${SSH_OPTS[@]}" "${VM_USER}@${VM_HOST}" "pg-dump" > "${DUMP_FILE}.partial" 2>>"$LOG_FILE"; then
  mv "${DUMP_FILE}.partial" "$DUMP_FILE"
  DUMP_SIZE=$(stat -c%s "$DUMP_FILE" 2>/dev/null || stat -f%z "$DUMP_FILE")
  if [[ "$DUMP_SIZE" -eq 0 ]]; then
    fail "pg_dump produced a zero-byte file"
  fi
  log "pg_dump OK, ${DUMP_SIZE} bytes"
else
  rm -f "${DUMP_FILE}.partial"
  fail "pg_dump over SSH failed"
fi

# (b) media rsync, via the VM's restricted rrsync command.
#
# The remote path is "/", not "media/". rrsync is invoked with
# /var/lib/matrix-synapse/media/ as its restricted root, so the client's paths
# are already relative to that directory — "media/" would resolve to
# media/media/ and find nothing. rrsync also rejects any path containing "..",
# so the mirror cannot walk out of the media tree.
log "rsync media -> ${MEDIA_DIR}"
if rsync -az --delete -e "ssh ${SSH_OPTS[*]}" \
    "${VM_USER}@${VM_HOST}:/" "${MEDIA_DIR}/" >>"$LOG_FILE" 2>&1; then
  log "media rsync OK"
else
  fail "media rsync failed"
fi

# (c) homeserver.yaml + conf.d + signing key, via the VM's tar-config
# dispatch command, unpacked into a dated directory.
CONFIG_SNAPSHOT="${CONFIG_DIR}/${DATE}"
log "config copy -> ${CONFIG_SNAPSHOT}"
mkdir -p "$CONFIG_SNAPSHOT"
if ssh "${SSH_OPTS[@]}" "${VM_USER}@${VM_HOST}" "tar-config" | tar -xf - -C "$CONFIG_SNAPSHOT" 2>>"$LOG_FILE"; then
  if [[ ! -s "${CONFIG_SNAPSHOT}/homeserver.yaml" ]]; then
    fail "config copy missing homeserver.yaml"
  fi
  log "config copy OK"
else
  fail "config copy failed"
fi

# Retention: prune dumps and dated config snapshots older than RETENTION_DAYS.
log "pruning dumps/config older than ${RETENTION_DAYS} days"
find "$DUMP_DIR" -maxdepth 1 -name 'synapse-*.dump' -mtime "+${RETENTION_DAYS}" -print -delete >>"$LOG_FILE" 2>&1
find "$CONFIG_DIR" -mindepth 1 -maxdepth 1 -type d -mtime "+${RETENTION_DAYS}" -print -exec rm -rf {} \; >>"$LOG_FILE" 2>&1

log "=== backup run OK ==="
