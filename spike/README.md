# spike/ — throwaway measurement rigs

Nothing here ships. Code in this directory exists to retire a risk and is deleted or frozen
once the decision it supports lands in Contract §11.

## TimelineSpike

The M0 timeline harness (S-12). It gates the SwiftUI vs AppKit timeline decision (S-15,
risk R-1).

- **Standalone SPM package.** It is deliberately not a member of `Mactrix.xcodeproj`, so it
  cannot conflict with parallel work on the app.
- **No matrix-rust-sdk, no Matrix code.** All data is synthetic. The question is list
  architecture, and the SDK would only add noise and build time.

Read `SCENARIOS.md` before running anything. It is the measurement protocol S-13 and S-14
must both follow.

### Build and run

```
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --package-path spike/TimelineSpike
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test  --package-path spike/TimelineSpike
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift run   --package-path spike/TimelineSpike TimelineSpikeApp
```

The GUI cannot be verified headlessly. `swift build` and `swift test` are the automated
gate; the numbers come from a human driving the window.

### Layout

```
TimelineSpike/
  Sources/TimelineSpikeCore/          library, no UI chrome of its own
    Random/SplitMix64.swift           seeded generator, explicit bit consumption
    Model/SpikeEvent.swift            event, sender, content, reaction, timeline item
    Generation/SpikeCorpus.swift      frozen word, emoji and caption pools
    Generation/SyntheticEventGenerator.swift
                                      pure function of (seed, index) over all of Int
    Store/TimelineStore.swift         loaded window, prepend, mutation, derived flags
    Drivers/Mutation.swift            the three mutation kinds
    Drivers/MutationDriver.swift      the storm, with the on/off-screen guarantee
    Drivers/PaginationDriver.swift    automatic and manual prepend
    Instrumentation/FrameStatistics.swift   histogram, percentiles, hitch count
    Instrumentation/FrameRecorder.swift     CADisplayLink sampling
    Instrumentation/AnchorProbe.swift       scroll-anchor drift measurement
    Harness/HarnessConfiguration.swift      settings and the JSON report shape
    Harness/SpikeHarness.swift              wiring, timers, report writing
    Renderer/TimelineRenderer.swift         the candidate seam
    Renderer/SpikeRowMetrics.swift          layout spec both candidates must match
    Renderer/SpikeRowView.swift             shared SwiftUI row
    Renderer/WorkloadFingerprint.swift      digest of the frozen row workload
  Sources/TimelineSpikeApp/           executable: window, console, HUD, placeholder
    Candidates/                       the measured renderers
  Tests/TimelineSpikeCoreTests/       generator determinism, driver invariants, instruments
```

### Adding a candidate (S-13, S-14)

1. Add one file to `Sources/TimelineSpikeApp/Candidates/` with a type conforming to
   `TimelineRenderer`.
2. Add one line to `RendererCatalog.all`.

Nothing else changes. The store, the drivers, the instruments and the console are shared, so
the two candidates are measured by the same code on the same data.

`SCENARIOS.md` §8 lists exactly what a candidate owes the harness.
