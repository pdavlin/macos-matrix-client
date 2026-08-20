import Foundation
import Testing
@testable import TimelineSpikeCore

@Suite("Synthetic generator determinism")
struct GeneratorDeterminismTests {
    private let seed: UInt64 = 0xABCD_1234_5678_9F01

    @Test("Two generators with the same seed produce identical events")
    func sameSeedSameEvents() {
        let first = SyntheticEventGenerator(seed: seed)
        let second = SyntheticEventGenerator(seed: seed)
        #expect(first.events(in: 0 ..< 2_000) == second.events(in: 0 ..< 2_000))
        #expect(first.events(in: -700 ..< -100) == second.events(in: -700 ..< -100))
    }

    @Test("A different seed produces a different timeline")
    func differentSeedDiffers() {
        let first = SyntheticEventGenerator(seed: seed)
        let second = SyntheticEventGenerator(seed: seed &+ 1)
        #expect(first.events(in: 0 ..< 500) != second.events(in: 0 ..< 500))
    }

    @Test("Range generation matches single-index generation")
    func rangeMatchesSingleIndex() {
        let generator = SyntheticEventGenerator(seed: seed)
        // Deliberately straddles two chunk boundaries and index zero.
        let range = -520 ..< 530
        let batch = generator.events(in: range)
        #expect(batch.count == range.count)
        for (offset, index) in range.enumerated() {
            #expect(batch[offset] == generator.event(at: index))
        }
    }

    @Test("Identifiers are the index line, contiguous and ascending")
    func identifiersFollowTheIndexLine() {
        let generator = SyntheticEventGenerator(seed: seed)
        let range = -100 ..< 900
        for (offset, event) in generator.events(in: range).enumerated() {
            #expect(event.id.rawValue == range.lowerBound + offset)
        }
    }

    @Test("Timestamps increase strictly, including across index zero")
    func timestampsAreMonotonic() {
        let generator = SyntheticEventGenerator(seed: seed)
        let events = generator.events(in: -1_100 ..< 1_100)
        for pair in zip(events, events.dropFirst()) {
            #expect(pair.1.timestamp > pair.0.timestamp)
        }
    }

    @Test("Prepending never overlaps or skips the loaded window")
    func prependIsContiguousWithTheWindow() {
        let generator = SyntheticEventGenerator(seed: seed)
        let loaded = generator.events(in: 0 ..< 100)
        let prepended = generator.events(in: -50 ..< 0)
        #expect(prepended.count == 50)
        guard let lastPrepended = prepended.last, let firstLoaded = loaded.first else {
            Issue.record("both batches must be non-empty")
            return
        }
        #expect(lastPrepended.id.rawValue + 1 == firstLoaded.id.rawValue)
        #expect(lastPrepended.timestamp < firstLoaded.timestamp)
    }

    @Test("The content mix covers one-line text, long text and images")
    func contentMixIsVaried() {
        let generator = SyntheticEventGenerator(seed: seed)
        let events = generator.events(in: 0 ..< 10_000)
        #expect(events.count == 10_000)

        var oneLine = 0
        var multiLine = 0
        var images = 0
        var longestBody = 0
        var aspectRatios: Set<Int> = []

        for event in events {
            switch event.content {
            case .text(let body):
                if body.lineCount == 1 {
                    oneLine += 1
                } else {
                    multiLine += 1
                }
                longestBody = max(longestBody, body.lineCount)
                #expect(body.lineCount >= 1)
                #expect(body.lineCount <= SyntheticEventGenerator.maximumLineCount)
                #expect(!body.paragraphs.isEmpty)
            case .image(let placeholder):
                images += 1
                #expect(placeholder.aspectRatio > 0)
                aspectRatios.insert(Int(placeholder.aspectRatio * 10))
            }
        }

        #expect(oneLine > 4_000)
        #expect(multiLine > 2_000)
        #expect(images > 500)
        #expect(longestBody >= 30, "the long tail must reach a tall body")
        #expect(aspectRatios.count > 10, "image heights must vary")
    }

    @Test("Sender runs group consecutive events without pinning one sender")
    func senderRunsExist() {
        let generator = SyntheticEventGenerator(seed: seed)
        let events = generator.events(in: 0 ..< 3_000)
        var runs = 0
        var longestRun = 1
        var current = 1
        for pair in zip(events, events.dropFirst()) {
            if pair.0.sender == pair.1.sender {
                current += 1
            } else {
                runs += 1
                longestRun = max(longestRun, current)
                current = 1
            }
        }
        #expect(runs > 400, "runs must break often enough to exercise grouping")
        #expect(longestRun >= 3, "runs must actually group")
        #expect(Set(events.map(\.sender.id)).count == SpikeSender.roster.count)
    }

    @Test("Floor division is correct across zero")
    func floorDivisionIsCorrect() {
        #expect(SyntheticEventGenerator.floorDiv(0, 512) == 0)
        #expect(SyntheticEventGenerator.floorDiv(511, 512) == 0)
        #expect(SyntheticEventGenerator.floorDiv(512, 512) == 1)
        #expect(SyntheticEventGenerator.floorDiv(-1, 512) == -1)
        #expect(SyntheticEventGenerator.floorDiv(-512, 512) == -1)
        #expect(SyntheticEventGenerator.floorDiv(-513, 512) == -2)
    }

    @Test("The unbiased draw stays inside its range")
    func randomDrawsStayInRange() {
        var generator = SplitMix64(seed: 42)
        for _ in 0 ..< 5_000 {
            let value = generator.int(in: 7 ..< 19)
            #expect(value >= 7)
            #expect(value < 19)
            let unit = generator.unitDouble()
            #expect(unit >= 0)
            #expect(unit < 1)
        }
    }
}

@Suite("Timeline store")
@MainActor
struct TimelineStoreTests {
    private let seed: UInt64 = 0x1111_2222_3333_4444

    @Test("The initial window is contiguous, ordered and annotated")
    func initialWindowIsSane() {
        let store = TimelineStore(seed: seed, initialEventCount: 1_200)
        #expect(store.items.count == 1_200)
        #expect(store.oldestIndex == 0)
        #expect(store.newestIndex == 1_199)
        for (offset, item) in store.items.enumerated() {
            #expect(item.id.rawValue == offset)
            #expect(store.itemIndex(for: item.id) == offset)
        }
        #expect(store.items[0].daySeparator != nil, "the first loaded item always opens a day")
        #expect(store.items.contains { $0.daySeparator != nil && $0.id.rawValue > 0 })
        #expect(store.items.contains { !$0.startsSenderRun }, "grouping must suppress some headers")
    }

    @Test("Prepending keeps the window contiguous and re-derives the seam")
    func prependKeepsInvariants() {
        let store = TimelineStore(seed: seed, initialEventCount: 400)
        let previousFirstID = store.items[0].id

        let inserted = store.prepend(count: 50)
        #expect(inserted == 0 ..< 50)
        #expect(store.items.count == 450)
        #expect(store.oldestIndex == -50)
        #expect(store.prependedBatchCount == 1)
        #expect(store.prependedEventCount == 50)

        for (offset, item) in store.items.enumerated() {
            #expect(item.id.rawValue == -50 + offset)
        }
        #expect(store.items[0].daySeparator != nil)

        // The item that used to be first is no longer guaranteed to open a day.
        guard let seamIndex = store.itemIndex(for: previousFirstID) else {
            Issue.record("the previously first item must still be loaded")
            return
        }
        #expect(seamIndex == 50)
        let seamDay = Calendar.spikeUTC.startOfDay(for: store.items[seamIndex].event.timestamp)
        let beforeDay = Calendar.spikeUTC.startOfDay(for: store.items[49].event.timestamp)
        #expect((store.items[seamIndex].daySeparator != nil) == (seamDay != beforeDay))
    }

    @Test("Timestamps stay ordered after repeated prepends")
    func repeatedPrependsStayOrdered() {
        let store = TimelineStore(seed: seed, initialEventCount: 300)
        for _ in 0 ..< 20 {
            store.prepend(count: 50)
        }
        #expect(store.items.count == 1_300)
        #expect(store.oldestIndex == -1_000)
        for pair in zip(store.items, store.items.dropFirst()) {
            #expect(pair.1.event.timestamp > pair.0.event.timestamp)
            #expect(pair.1.id.rawValue == pair.0.id.rawValue + 1)
        }
    }

    @Test("A mutation for an unloaded event is ignored")
    func mutationOutsideTheWindowIsIgnored() {
        let store = TimelineStore(seed: seed, initialEventCount: 100)
        #expect(store.apply(.addReaction(EventID(-5), key: "x")) == nil)
        #expect(store.appliedMutationCount == 0)
    }
}
