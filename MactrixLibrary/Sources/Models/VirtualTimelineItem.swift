import Foundation

public enum VirtualTimelineItem {
    /**
     * A divider between messages of different day or month depending on
     * timeline settings.
     */
    case dateDivider(
        date: Date
    )
    /**
     * The user's own read marker.
     */
    case readMarker
    /**
     * The timeline start, that is, the *oldest* event in time for that room.
     */
    case timelineStart
    /**
     * The source note of a merged timeline (MATRIX-142): the rows below it, up
     * to the next source note, come from the member room the label names.
     * Its row height is fixed (`MergedSourceLabel.rowHeight`).
     */
    case mergedSource(MergedSourceLabel)
}
