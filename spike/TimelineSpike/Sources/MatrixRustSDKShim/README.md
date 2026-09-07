# MatrixRustSDK — shim module

This target is **named** `MatrixRustSDK` on purpose. The production timeline container
files carry `import MatrixRustSDK`, and the harness compiles those files verbatim
(they are symlinks, see `../ProductionTimeline/Production`). Naming the shim module
after the real one is what lets the real import line resolve inside the spike package
without editing a single production byte.

Nothing here talks to a homeserver, and nothing here is a copy of the real bindings.
It declares only the handful of SDK **shapes** the three container files name:

| Symbol | Why the container needs it |
| --- | --- |
| `TimelineUniqueId` | the diffable data source's item identifier |
| `TimelineItem` | the element type of `LiveTimeline.displayItems` |
| `EventTimelineItem` | what a `.message`/`.state` row casts its event back to |
| `TimelineItemContent`, `MsgLikeContent`, `MsgLikeKind` | the row-kind switch |
| `EventOrTransactionId` | focus requests |
| `PaginationStatus` | the pagination decoration row |

If a future timeline story makes the container name a new SDK symbol, this module
fails to compile and the gate goes red. That is the intended behaviour: the shim is
the written-down contract between the container and the SDK, and it has to keep pace.
