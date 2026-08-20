# Exported Xcode agent skills

## What these are

These directories are Xcode agent skills exported from
Xcode 27.0 (build 27A5237l), the beta at
`/Applications/Xcode-beta.app`. Each skill is a copy of
Apple-authored guidance that supersedes prior model training on the
covered topic. Per CLAUDE.md, read these before Liquid Glass or
macOS 26/27 API work.

## Export commands and outcome

Exploration, in order:

```
xcrun --find agent
```

Output: `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/agent`.
The tool exists in this Xcode build.

```
xcrun agent --help
```

Output showed one command, `skills`, described as "Inspect and export
Xcode-provided skills".

```
xcrun agent skills list
```

There is no `list` subcommand. The tool printed its usage for
`skills`, which has exactly one subcommand: `export`. Skill discovery
happens by running `export` and reading the names it prints.

```
xcrun agent skills export -h
```

Output: `export` takes `--output-dir <path>` and `--replace-existing`.
There is no flag to select skills by name; `export` always exports
every skill this Xcode build knows about.

```
xcrun agent skills export --output-dir <scratch-dir>
```

Output:

```
Exported 10 skills to <scratch-dir>
  ✓ swiftui-specialist
  ✓ device-interaction
  ✓ app-intents-specialist
  ✓ uikit-app-modernization
  ✓ swiftui-whats-new-27
  ✓ audit-xcode-security-settings
  ✓ building-document-based-swiftui-applications
  ✓ app-intents-whats-new-27
  ✓ modernize-tests
  ✓ adopt-c-bounds-safety
```

Ten skills were available. This story asked for two: "SwiftUI
Specialist" and "What's New in SwiftUI". The exported names
`swiftui-specialist` and `swiftui-whats-new-27` are those two skills
(the "27" in the second name is this Xcode build's target OS version).
Both were copied byte-exact from the scratch export into this
directory. The other eight exported skills were discarded; they are
out of scope for S-10.

## Directories in this story

- `swiftui-specialist/` — SwiftUI best practices: view structure,
  data flow (`@State`, `@Binding`, `@Observable`), `@Environment` and
  `@Entry`, conditional modifiers, `ForEach`/`List` row identity,
  localization, soft-deprecated APIs.
- `swiftui-whats-new-27/` — New SwiftUI APIs and behavior changes for
  the 2027 OS releases: the `@State` macro, `@ViewBuilder`/content
  builder changes, `reorderable()`, `AsyncImage` caching, swipe
  actions outside `List`, toolbar overflow and pinning, and
  item-binding presentation.

Each has a `SKILL.md` and a `references/` directory of topic files, as
exported. Do not hand-edit these; re-run the export if the content
needs to change (see below).

## Refresh procedure

Re-run the export if the Xcode version changes or the skill content is
suspected stale:

```
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcrun agent skills export --output-dir <scratch-dir> --replace-existing
```

Then copy `swiftui-specialist/` and `swiftui-whats-new-27/` from the
scratch directory over the ones in this directory, byte-exact, and
record the new Xcode version and build number at the top of this file.
