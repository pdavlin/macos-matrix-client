# Epic E-HS-01 — Homeserver: exe.dev primary, davbuntu standby

| | |
|---|---|
| **Milestone** | Contract-external prerequisite; gates M0 Cluster B (S-05 through S-08) and the M0 exit criteria |
| **Decisions consumed** | Q-8 hosting (§11, 2026-08-20): exe.dev VM primary, davbuntu cold-standby; hot failover ruled out |
| **Decisions produced** | Server name + delegation design (S-17, §11) |
| **Reference** | `docs/SYNAPSE-MIGRATION-PLAN.md` — invariants, standing backups, procedures |
| **Status** | Draft — 2026-08-20 |

## Goal

A running Synapse the client project can log into: server name on davlin.io via `.well-known`
delegation served from Cloudflare's edge, Synapse + Postgres on a dedicated exe.dev VM,
`@patrick` (prod) and `@dev` (test) accounts, standing backups to davbuntu, and the migration
plan rehearsed once for real. Beeper hybrid on sectional-cache stays untouched (interim).

## Exit criteria (binary)

- [ ] `@patrick:davlin.io` and `@dev:davlin.io` exist; client login works via well-known discovery.
- [ ] Federation lookup resolves through the Worker-served `.well-known` (verified from an external tester).
- [ ] Cloudflare proxy is NOT in the Matrix data path (delegation target is the VM's exe.xyz name, direct).
- [ ] Nightly Postgres dump + media rsync + config/key copies land on davbuntu under `/srv/synapse-standby/`.
- [ ] Delegation-drift probe alerts if served well-known differs from the committed copy.
- [ ] Migration plan executed once end-to-end (failover to davbuntu and back); plan updated to v2 with findings; copies on both hosts refreshed.
- [ ] M0 Cluster B (S-05..S-08) unblocked and started against `@dev:davlin.io`.

## Stories

- **S-17 Server name decision record** — confirm `@patrick:davlin.io` apex naming and the delegation design (Worker-served well-known, target = VM exe.xyz name, proxy out of path); dated §11 row. Gates everything.
- **S-18 Provision Synapse VM** — new exe.dev VM, Synapse + Postgres, `server_name: davlin.io`, TLS via exe.xyz, no accounts yet.
- **S-19 Delegation live** — Cloudflare Worker serving `/.well-known/matrix/server` + `/client` (CORS), verified externally; 2FA audit on Porkbun + Cloudflare.
- **S-20 Accounts and first login** — `@patrick` + `@dev`, registration closed, client logs in via discovery; dev-account rule (CLAUDE.md hard rule 3) restated in credentials handling.
- **S-21 Standing backups + standby prep + drift probe** — per the migration plan: nightly dump/rsync/config to davbuntu `/srv/synapse-standby/`, Postgres + ingress pre-staged on davbuntu, delegation-drift probe.
- **S-22 Migration rehearsal** — execute failover to davbuntu and failback per the plan, while the server carries no irreplaceable traffic; update plan to v2; re-copy to both hosts.

## Sequencing

S-17 → S-18 → S-19 → S-20 → (S-21 → S-22); Cluster B can start after S-20, parallel to S-21/S-22.

## Out of scope

mautrix bridge migration off Beeper (own epic if ever), federation hardening beyond defaults,
TURN/coturn (calls deferred), server-side search, any client work.
