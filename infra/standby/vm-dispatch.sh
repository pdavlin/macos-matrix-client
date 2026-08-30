#!/usr/bin/env bash
# S-21 forced-command dispatcher, installed on the primary VM
# (davlin-matrix.exe.xyz) at /home/synbackup/bin/dispatch.sh, owned by
# synbackup, mode 750.
#
# This is the ONLY thing the backup automation is allowed to run, and since
# S-23 it is reached two different ways. It must behave identically through
# both:
#
#   1. sshd forced command. authorized_keys carries
#      command="/home/synbackup/bin/dispatch.sh" for the dedicated automation
#      key (see RESTORE-NOTES.md). sshd runs that as $SHELL -c "<that path>"
#      and puts the client's actual request in $SSH_ORIGINAL_COMMAND.
#
#   2. Tailscale SSH. It ignores authorized_keys entirely — forced commands
#      and the no-pty/no-port-forwarding options with them — and executes the
#      account's login shell. So since S-23 this script IS synbackup's login
#      shell (chsh'd via usermod), and the request arrives as:
#          dispatch.sh -c "<command>"
#
# Ordering matters. Once this script is the login shell, path 1 also invokes
# it as `-c /home/synbackup/bin/dispatch.sh`, so $SSH_ORIGINAL_COMMAND must
# win over the -c argument. Reverse the precedence and the forced-command
# path dispatches on the script's own filename and rejects everything.
#
# Why the login shell had to change at all: before S-23, synbackup's shell was
# /bin/bash. Enabling Tailscale SSH would then have handed an interactive bash
# to anyone the ACL admitted — on an account whose sudoers can run
# `tar -cf -` over homeserver.signing.key. That is a homeserver identity
# compromise, so the whitelist has to live somewhere Tailscale SSH respects.
#
# Three whitelisted operations:
#   pg-dump      -> pg_dump the synapse DB as the postgres role (sudo, one
#                   fixed command, no argument passthrough)
#   tar-config   -> tar homeserver.yaml + conf.d/ + signing key to stdout
#                   (sudo, one fixed command)
#   rsync --server ...  (sent by an rsync client, not typed literally) ->
#                   handed to rrsync, read-only, scoped to the media dir.
#                   No sudo: synbackup is a member of the matrix-synapse
#                   group so it can read the media tree directly.
#
# Anything else — including a bare interactive login — is rejected and logged.

set -uo pipefail

requested="${SSH_ORIGINAL_COMMAND:-}"

if [ -z "$requested" ] && [ "${1:-}" = "-c" ]; then
  requested="${2:-}"
fi

case "$requested" in
  "pg-dump")
    exec sudo -n -u postgres /usr/bin/pg_dump -Fc synapse
    ;;
  "tar-config")
    exec sudo -n /usr/bin/tar -cf - -C /etc/matrix-synapse homeserver.yaml conf.d homeserver.signing.key
    ;;
  rsync\ --server*)
    # rrsync validates that the request stays within the given path and is
    # read-only (-ro); it execs the real rsync --server itself.
    #
    # rrsync insists on being invoked via sshd: it reads the client's request
    # out of SSH_ORIGINAL_COMMAND and aborts with "Not invoked via sshd" if
    # that is unset. Tailscale SSH never sets it, so re-export what we parsed
    # from the -c argument. Without this the media sync is the one whitelisted
    # operation that silently fails over the tailnet.
    export SSH_ORIGINAL_COMMAND="$requested"
    exec /usr/bin/rrsync -ro /var/lib/matrix-synapse/media/
    ;;
  *)
    logger -t synbackup-dispatch "rejected command: ${requested:-<empty>}"
    echo "command not permitted" >&2
    exit 1
    ;;
esac
