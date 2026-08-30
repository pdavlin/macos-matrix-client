# Tailnet policy artifacts (S-23)

## `acl-before-s23.json`

The tailnet ACL exactly as it stood before S-23, fetched from the Tailscale
API on 2026-08-29. This is the restore point. If a later policy change breaks
connectivity, this is what to put back.

Note what it shows: `grants` is `* -> *` on all IPs. Network reachability
between every device on the tailnet is already unrestricted. S-23 did not
change that and did not try to — narrowing `grants` touches all 20 devices and
is its own piece of work. What S-23 scopes is Tailscale **SSH**, which is a
separate gate.

## What S-23 added

Two additive changes, and nothing else. Applied 2026-08-30 after the API's own
`/acl/validate` returned clean:

```json
"tagOwners": {
  "tag:matrix-hs": ["autogroup:admin"]
}
```

```json
"ssh": [
  {
    "action": "accept",
    "src":    ["pdavlin@github"],
    "dst":    ["tag:matrix-hs"],
    "users":  ["synbackup"]
  }
]
```

`action` is `accept`, not `check`. `check` forces a periodic browser re-auth,
which would break unattended backups.

### Why `src` is an identity and not `davbuntu`

The story specified `src: davbuntu`. That is not expressible — Tailscale
rejects it:

```
{"message":"[ssh] \"davbuntu\": hosts are not allowed"}
```

SSH rules take identities, groups, autogroups or tags. Never a host or an IP.

The closest alternative was tagging davbuntu, and it was rejected deliberately.
The pre-existing rule is `src autogroup:member -> dst autogroup:self`, and a
tagged device leaves `autogroup:self`. Tagging davbuntu would have silently
removed Patrick's own Tailscale SSH access to it. Patrick's instruction was
that access to davbuntu is imperative, so davbuntu is untagged and untouched.

The security value here sits in the destination and the login user, both of
which stay narrow: only `tag:matrix-hs`, only as `synbackup`, whose shell is
the command whitelist.

## Re-fetching the live policy

```
ssh davlin-matrix.exe.xyz \
  'curl -s -H "Accept: application/json" \
   https://tailscale.int.exe.xyz/api/v2/tailnet/-/acl'
```

`tailscale.int.exe.xyz` is an exe.dev-internal proxy that injects Tailscale API
credentials. It resolves only from inside exe.dev, so this must be run on a VM,
not from a laptop.
