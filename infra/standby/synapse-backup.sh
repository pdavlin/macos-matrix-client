#!/usr/bin/env bash
# S-21 standing backup pipeline. Runs on davbuntu (cron, nightly).
#
# STATUS as of S-21: not yet installed on davbuntu. Two blockers are open
# — see infra/standby/RESTORE-NOTES.md ("Blocker A" and "Blocker B") —
# before this script can run for real. It is committed here as the
# reviewed, ready-to-install target state.
#
# Pulls three things from the exe.dev primary (davlin-matrix.exe.xyz) over
# SSH, using the dedicated read-only automation key (see
# infra/standby/vm-dispatch.sh and RESTORE-NOTES.md for the VM-side setup):
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

VM_HOST="davlin-matrix.exe.xyz"
VM_USER="synbackup"
SSH_KEY="/srv/synapse-standby/.ssh/synbackup_ed25519"

ROOT="/srv/synapse-standby"
DUMP_DIR="${ROOT}/dumps"
MEDIA_DIR="${ROOT}/media"
CONFIG_DIR="${ROOT}/config"
LOG_FILE="${ROOT}/backup.log"

RETENTION_DAYS=14
DATE="$(date -u '+%Y-%m-%d')"

SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=15 -o IdentitiesOnly=yes)

mkdir -p "$DUMP_DIR" "$MEDIA_DIR" "$CONFIG_DIR"

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" | tee -a "$LOG_FILE"
}

fail() {
  log "ERROR: $1"
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

# (b) media rsync, via the VM's restricted rrsync forced command.
log "rsync media -> ${MEDIA_DIR}"
if rsync -az --delete -e "ssh ${SSH_OPTS[*]}" \
    "${VM_USER}@${VM_HOST}:media/" "${MEDIA_DIR}/" >>"$LOG_FILE" 2>&1; then
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
