import TimelineSpikeCore

/// Every renderer the harness can show.
///
/// S-13 and S-14 each add one line here and one file next to `PlaceholderRenderer`. Nothing
/// else in the harness changes.
enum RendererCatalog {
    static let all: [RendererDescriptor] = [
        RendererDescriptor(PlaceholderRenderer.self),
        RendererDescriptor(AppKitTableRenderer.self),
    ]

    static var `default`: RendererDescriptor {
        guard let first = all.first else {
            preconditionFailure("RendererCatalog must contain at least one renderer")
        }
        return first
    }
}
