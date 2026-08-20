# Synapse Migration Plan

| | |
|---|---|
| **Primary host** | exe.dev VM (name TBD at deployment — NOT sectional-cache, which runs the Beeper bridges) |
| **Failover / standby host** | davbuntu (Ubuntu 24.04, local homelab) |
| **Server name** | TBD before first account creation — a davlin.io name with `.well-known` delegation. THE SERVER NAME NEVER CHANGES. |
| **Source of truth** | This file in the repo (`docs/SYNAPSE-MIGRATION-PLAN.md`). Copies on both hosts are convenience copies; re-copy after each edit. |
| **Status** | v1 draft — written before Synapse deployment. The deployment story fills every TBD and tests this plan once. |

## Invariants — read before any migration

1. **Never run two Synapse instances for the same server name at the same time.** Not even briefly. Split-brain diverges the event graph and can re-serve consumed E2EE one-time keys.
2. The identity of the server is: the **server name** + the **signing key** (`homeserver.signing.key`). These never change. The hosting is a pointer aimed by `.well-known` delegation on davlin.io.
3. Three things move together or not at all: **Postgres database**, **media store**, **signing key + config**. A restore that is missing or behind on any one of them is a stale restore (see Warnings).

## Standing backups (prerequisite, set up with deployment)

- Nightly `pg_dump` from the primary, shipped to davbuntu.
- Media store rsync from the primary to davbuntu, same cadence.
- `homeserver.yaml`, `homeserver.signing.key`, and bridge/appservice registration files copied to davbuntu on every change.
- Target layout on davbuntu: `/srv/synapse-standby/` — dumps, media, keys, config, dated.

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
