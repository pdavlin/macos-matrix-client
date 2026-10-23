# Synapse Migration Plan

| | |
|---|---|
| **Primary host** | exe.dev VM `davlin-matrix` (https://davlin-matrix.exe.xyz/) |
| **Failover / standby host** | davbuntu (Ubuntu 24.04, local homelab) |
| **Server name** | **davlin.io** (decided S-17, contract §11 2026-08-20), delegated via Worker-served `.well-known` pointing at `davlin-matrix.exe.xyz:443`. THE SERVER NAME NEVER CHANGES. |
| **Source of truth** | This file in the repo (`docs/SYNAPSE-MIGRATION-PLAN.md`). Copies on both hosts are convenience copies; re-copy after each edit. |
| **Status** | Deployed 2026-08-20 (S-18). matrix-synapse-py3 1.159.0+noble1 installed via the matrix.org apt repo, Postgres 16.15 backend (`synapse` DB, C collation). Registration disabled; federation left on defaults. No accounts created yet (S-20). |

## Invariants — read before any migration

1. **Never run two Synapse instances for the same server name at the same time.** Not even briefly. Split-brain diverges the event graph and can re-serve consumed E2EE one-time keys.
2. The identity of the server is: the **server name** + the **signing key** (`homeserver.signing.key`). These never change. The hosting is a pointer aimed by `.well-known` delegation on davlin.io.
3. Three things move together or not at all: **Postgres database**, **media store**, **signing key + config**. A restore that is missing or behind on any one of them is a stale restore (see Warnings).

## Standing backups (prerequisite, set up with deployment)

- Nightly `pg_dump` from the primary, shipped to davbuntu.
- Media store rsync from the primary to davbuntu, same cadence.
- `homeserver.yaml`, `homeserver.signing.key`, and bridge/appservice registration files copied to davbuntu on every change.
- Target layout on davbuntu: `/srv/synapse-standby/` — dumps, media, keys, config, dated.

## Bridges (E-HS-03)

Bridges are upstream mautrix appservices on the Synapse host (contract §11, 2026-10-23, MATRIX-69). They are part of the server's state: a restore without them strands every bridged room.

| Item | Location on the primary |
|---|---|
| Binary (pinned, sha256-checked) | `/opt/mautrix-<net>/mautrix-<net>` |
| Config (DB URI, as/hs tokens, crypto pickle key) | `/opt/mautrix-<net>/config.yaml`, mode 0600, owner `mautrix-<net>` |
| Registration (bridge copy) | `/opt/mautrix-<net>/registration.yaml` |
| Registrations loaded by Synapse | `/etc/matrix-synapse/appservices/{doublepuppet,<net>}.yaml`, `root:matrix-synapse` 0640 |
| Synapse include | `/etc/matrix-synapse/conf.d/appservices.yaml` |
| Database | Postgres role + DB `mautrix_<net>` on the Synapse instance |
| Service | systemd `mautrix-<net>.service`, user `mautrix-<net>`, appservice on `127.0.0.1` |

Deployed: Slack (`mautrix-slack` v0.2610.0, port 29335, bot `@slackbot:davlin.io`, puppets `@slack_*`). The shared `doublepuppet` registration serves every bridge.

**Backup coverage (MATRIX-70, live 2026-10-23):** the nightly davbuntu run dumps each bridge DB to `dumps/mautrix_<net>-<date>.dump` (forced command `pg-dump-mautrix_<net>`), copies `/opt/mautrix-<net>/{config,registration}.yaml` to `config/<date>/bridges/` (`tar-bridges`), and `tar-config` now includes `appservices/`. Each new bridge needs its own `pg-dump-<db>` entry in `/home/synbackup/bin/dispatch.sh`, a matching exact-command line in `/etc/sudoers.d/synbackup`, its DB name in the davbuntu loop, and its paths in `tar-bridges`. The bridge config holds the crypto pickle key: losing it means resetting bridge encryption and a fresh network login.

**Restore order** (failover step 3 and 4 add these):

1. Restore each `mautrix_<net>` dump into Postgres alongside `synapse` (create the role first).
2. Place `/etc/matrix-synapse/appservices/` and `conf.d/appservices.yaml` with the rest of the Synapse config.
3. Install the same pinned bridge binary, the system user, `/opt/mautrix-<net>/` (config + registration), and the systemd unit.
4. Start Synapse first, then each bridge. Confirm the bot profile resolves and the bridge log has no `ERR` lines.
5. Never run a bridge on two hosts at once: same rule as invariant 1, because both would answer for the same appservice namespace.

## Migration: exe.dev → davbuntu (failover)

1. Stop Synapse on the exe.dev primary. If the host is dead, make sure it stays dead (VM stopped or deleted) before step 4.
2. Take a final `pg_dump` and a final media rsync if the primary is still reachable. If not, use the newest standing backup and read the Warnings section first.
3. On davbuntu: restore the dump into Postgres, place the media store, install `homeserver.yaml` + signing key, install Synapse (same major version as the primary ran).
4. Start Synapse on davbuntu. Confirm it serves `/_matrix/client/versions` locally.
5. Repoint ingress: davlin.io `.well-known/matrix/{server,client}` → davbuntu's public endpoint (reverse proxy + TLS on davbuntu must already exist — set up and tested at deployment time, not during an outage).
6. Verify: log in from the Mac client; send/receive in an E2EE room; check federation with one remote server if federation is on.
7. Update the roles table at the top of this file and re-copy it to both hosts.

## Failback: davbuntu → exe.dev

Same procedure in reverse. davbuntu becomes the source, a fresh exe.dev VM the target. Because the server name and signing key are unchanged, remotes and devices notice nothing.

## Leaving exe.dev permanently

Identical to failover; davbuntu (or any future host) simply stays primary. Nothing about the account, E2EE identity, or rooms is tied to exe.dev — that is the entire point of delegation-based naming.

## Warnings

- **Stale restore is the dangerous case.** If the primary died and the newest backup is behind, some events and used one-time keys are lost. Expect some undecryptable messages and possibly device re-verification. Acceptable for personal scale; do not "fix" it by briefly resurrecting the old primary — that is invariant 1.
- Do not migrate during a Synapse version window that requires DB migrations you have not read about. Match versions, migrate, then upgrade.
- The M3 client search index is on the Mac, not the server — no server migration step for it.
