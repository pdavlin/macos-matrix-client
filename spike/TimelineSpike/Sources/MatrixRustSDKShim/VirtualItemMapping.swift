import Models

public extension VirtualTimelineItem {
    /// The container maps an SDK virtual item onto the platform-neutral model
    /// with `asModel`. The shim already vends the model type, so the mapping
    /// is the identity — the name exists so the production call site compiles
    /// unchanged.
    var asModel: VirtualTimelineItem { self }
}
