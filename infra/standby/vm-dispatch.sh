#!/usr/bin/env bash
# S-21 forced-command dispatcher, installed on the primary VM
# (davlin-matrix.exe.xyz) at /home/synbackup/bin/dispatch.sh, owned by
# synbackup, mode 750.
#
# This is the ONLY thing the dedicated backup automation key is allowed to
# run. It is wired in as the forced command for that key in synbackup's
# authorized_keys (see RESTORE-NOTES.md), so no other command ever reaches
# a shell for this account, regardless of what the SSH client requests.
#
# Three whitelisted operations, dispatched on $SSH_ORIGINAL_COMMAND:
#   pg-dump      -> pg_dump the synapse DB as the postgres role (sudo, one
#                   fixed command, no argument passthrough)
#   tar-config   -> tar homeserver.yaml + conf.d/ + signing key to stdout
#                   (sudo, one fixed command)
#   rsync --server ...  (sent by an rsync client, not typed literally) ->
#                   handed to rrsync, read-only, scoped to the media dir.
#                   No sudo: synbackup is a member of the matrix-synapse
#                   group so it can read the media tree directly.
#
# Anything else is rejected and logged.

set -uo pipefail

case "${SSH_ORIGINAL_COMMAND:-}" in
  "pg-dump")
    exec sudo -n -u postgres /usr/bin/pg_dump -Fc synapse
    ;;
  "tar-config")
    exec sudo -n /usr/bin/tar -cf - -C /etc/matrix-synapse homeserver.yaml conf.d homeserver.signing.key
    ;;
  rsync\ --server*)
    # rrsync validates that the request stays within the given path and is
    # read-only (-ro); it execs the real rsync --server itself.
    exec /usr/bin/rrsync -ro /var/lib/matrix-synapse/media/
    ;;
  *)
    logger -t synbackup-dispatch "rejected command: ${SSH_ORIGINAL_COMMAND:-<empty>}"
    echo "command not permitted" >&2
    exit 1
    ;;
esac
