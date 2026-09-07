import ProductionTimeline
import TimelineSpikeCore

/// Every renderer the harness can show.
///
/// S-13 and S-14 each add one line here and one file next to `PlaceholderRenderer`. Nothing
/// else in the harness changes.
enum RendererCatalog {
    static let all: [RendererDescriptor] = [
        RendererDescriptor(PlaceholderRenderer.self),
        RendererDescriptor(AppKitTableRenderer.self),
        // S-39: not a candidate. This is the shipping container, mounted here so
        // the thresholds the candidates set can be checked against the code that
        // actually ships.
        RendererDescriptor(ProductionTimelineRenderer.self),
    ]

    static var `default`: RendererDescriptor {
        guard let first = all.first else {
            preconditionFailure("RendererCatalog must contain at least one renderer")
        }
        return first
    }

    /// The descriptor with the given id, or `nil`. Used by the automated runner
    /// to select a renderer without a click.
    static func renderer(withID id: String) -> RendererDescriptor? {
        all.first { $0.id == id }
    }
}
