import Foundation

/// Identity rules for the rows the timeline container hands to AppKit's
/// diffable data source (MATRIX-130).
///
/// `NSDiffableDataSourceSnapshot` raises an Objective-C exception when an
/// identifier is not unique. The container mutates its snapshot inside
/// SwiftUI's view update, which runs in an Observation tracking scope. An
/// exception that unwinds through that scope skips the Swift cleanup that
/// restores Observation's thread-local access list, and AppKit catches the
/// exception, so the app continues with a dangling pointer. The next
/// observable read on the main thread then crashes far from the cause.
///
/// The container checks every identifier against these rules first, and
/// resynchronizes instead of mutating the snapshot when a check fails.
public enum TimelineRowIdentity {
    /// True when inserting `ids` keeps every identifier unique: no identifier
    /// repeats inside `ids`, and none is already present.
    ///
    /// - Parameters:
    ///   - ids: the identifiers about to be inserted, in insert order.
    ///   - isPresent: reports whether an identifier is already in the
    ///     snapshot. Called at most once per identifier.
    /// - Returns: false if the insert would duplicate an identifier.
    public static func canInsert(_ ids: [String], isPresent: (String) -> Bool) -> Bool {
        var seen = Set<String>()
        seen.reserveCapacity(ids.count)
        for id in ids {
            guard seen.insert(id).inserted, !isPresent(id) else { return false }
        }
        return true
    }

    /// Removes the elements whose identifier an earlier element already has.
    ///
    /// Order is kept and the first occurrence wins, so the newest copy of a
    /// duplicated row stays in a newest-first array.
    ///
    /// - Parameters:
    ///   - elements: the rows in display order.
    ///   - id: the identifier of one element.
    /// - Returns: the unique elements, and the identifiers of the elements
    ///   that were removed (empty when every identifier was unique).
    public static func removingDuplicates<Element>(
        _ elements: [Element],
        id: (Element) -> String
    ) -> (unique: [Element], removedIds: [String]) {
        var seen = Set<String>()
        seen.reserveCapacity(elements.count)
        var unique: [Element] = []
        unique.reserveCapacity(elements.count)
        var removedIds: [String] = []
        for element in elements {
            let elementId = id(element)
            if seen.insert(elementId).inserted {
                unique.append(element)
            } else {
                removedIds.append(elementId)
            }
        }
        return (unique, removedIds)
    }
}
