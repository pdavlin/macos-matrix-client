#!/usr/bin/env python3
"""Seed the 15 M0 stories from docs/epics/E-M0-01-foundation.md into Plane.

Idempotent: skips any story whose "S-xx" prefix already exists in the project.
Requires PLANE_API_KEY in the environment (or .claude/settings.local.json).
"""
import json
import os
import sys
import urllib.request

BASE = "https://pd-plane.exe.xyz/api/v1/workspaces/agent-coworking"
PROJECT = "634541aa-001b-400e-a61c-c87c5ecbf3fe"
EPIC = "docs/epics/E-M0-01-foundation.md"

STORIES = [
    ("S-01 Fork and first build",
     "Fork Mactrix into matrix-mac-client. Remove the upstream remote. Set the bundle ID and ad-hoc signing. Fix version-drift build errors only. Output: green build of the unmodified app.",
     "Cluster A"),
    ("S-02 Pin and verify matrix-rust-components-swift",
     "Pin the exact version in Package.resolved. Inspect the XCFramework for a macos-arm64 slice. If absent: stand up the from-source build and script it in scripts/build-ffi.sh. Closes Q-4, feeds R-3. Record in contract S11.",
     "Cluster A"),
    ("S-03 Licensing check",
     "Read the Mactrix license and the SDK package licenses at the pinned version. Record obligations in contract S11. Output: LICENSE and THIRD_PARTY_NOTICES.md. Closes Q-1 and Q-2.",
     "Cluster A"),
    ("S-04 Deployment target decision",
     "Set the minimum deployment target to macOS 26. Confirm build and run on the primary dev machine. Record the decision in contract S11. Closes Q-3.",
     "Cluster A"),
    ("S-05 Login: password and SSO",
     "Point login at the homelab homeserver. Confirm .well-known discovery. Test password and SSO login with the dev account. Fix only what blocks login; log other Mactrix bugs as M1 candidates.",
     "Cluster B"),
    ("S-06 Session persistence",
     "Confirm the session restores from the keychain after relaunch. Decide: keep the Mactrix store layout or migrate to current SDK defaults. Migrate now if chosen — stores are cheap to reset today. Verify the keychain entitlement. Closes Q-5. Record in contract S11.",
     "Cluster B"),
    ("S-07 Device verification",
     "Run emoji verification in both directions against a second device. Confirm cross-signing trust. Confirm key backup restore so history decrypts.",
     "Cluster B"),
    ("S-08 E2EE room decrypts",
     "Open a bridged E2EE DM on the dev account. Confirm live and back-paginated messages decrypt. Record any unable-to-decrypt cases and their causes.",
     "Cluster B"),
    ("S-09 CLAUDE.md and build scripts",
     "Update CLAUDE.md for the post-fork repo (remove the [after S-xx] markers). Write scripts/build.sh, test.sh, lint.sh wrapping xcodebuild with xcbeautify, non-zero exit on failure. Output: a fresh agent session builds and tests from the instructions alone.",
     "Cluster C"),
    ("S-10 Agent skills and FFI reference",
     "Export the Xcode SwiftUI agent skills to docs/skills/. Vendor the generated FFI Swift interfaces to docs/ffi/ with scripts/refresh-ffi-docs.sh for SDK bumps.",
     "Cluster C"),
    ("S-11 Formatting, lint, and test scaffolding",
     "Add SwiftFormat and SwiftLint with configs; commit the one-time reformat as a no-logic commit. Add swift-snapshot-testing and one trivial snapshot test that runs headlessly via scripts/test.sh.",
     "Cluster C"),
    ("S-12 Timeline spike: harness and synthetic data",
     "Throwaway TimelineSpike target, no SDK dependency. Generate 10k+ mixed-height synthetic events. Add mutation and back-pagination drivers. Instrument frame time, hitch count, and scroll anchor drift.",
     "Cluster D"),
    ("S-13 Timeline spike: pure SwiftUI candidate",
     "Inverted list via List or ScrollView + LazyVStack with scrollPosition and defaultScrollAnchor. Run the S-12 harness. Record p95 frame time, hitches, anchor drift.",
     "Cluster D"),
    ("S-14 Timeline spike: AppKit-backed candidate",
     "NSTableView or NSCollectionView in NSViewRepresentable. Variable heights, prepend without jump, in-place height updates. Run the S-12 harness. Record the same numbers.",
     "Cluster D"),
    ("S-15 Timeline decision",
     "Compare candidates against the contract S7 budget. Record the decision and numbers in contract S11. Delete the losing candidate; keep the harness for M1 regression use. Gate for M1.",
     "Cluster D"),
]


def api(method, path, body=None):
    key = os.environ.get("PLANE_API_KEY")
    if not key:
        with open(".claude/settings.local.json") as f:
            key = json.load(f)["env"]["PLANE_API_KEY"]
    req = urllib.request.Request(
        f"{BASE}{path}",
        method=method,
        headers={"X-API-Key": key, "Content-Type": "application/json"},
        data=json.dumps(body).encode() if body else None,
    )
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


def main():
    existing = set()
    page = api("GET", f"/projects/{PROJECT}/issues/?per_page=100")
    for issue in page.get("results", []):
        existing.add(issue["name"].split(" ")[0])

    created = 0
    for name, summary, cluster in STORIES:
        sid = name.split(" ")[0]
        if sid in existing:
            print(f"skip   {name} (exists)")
            continue
        desc = (
            f"<p>{summary}</p>"
            f"<p>{cluster} of epic E-M0-01. Full story text: {EPIC} in the repo.</p>"
            "<p>Definition of done: builds clean, tests pass incl. snapshots, "
            "manual smoke on the dev account where applicable, no new SwiftLint violations.</p>"
        )
        api("POST", f"/projects/{PROJECT}/issues/", {"name": name, "description_html": desc})
        print(f"create {name}")
        created += 1
    print(f"done: {created} created, {len(STORIES) - created} skipped")


if __name__ == "__main__":
    main()
