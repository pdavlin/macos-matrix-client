import SwiftUI
import Tokens

/// A file-style attachment row: an icon, a filename, and an optional detail
/// line (file size, audio duration).
///
/// Presentational only — the app target wires the download, Quick Look, and
/// save-to-Downloads actions around it.
public struct AttachmentRowView: View {
    let icon: Image
    let title: String
    let subtitle: String?

    @Environment(\.timelineTypography) private var typography

    public init(icon: Image, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack {
            icon
            Text(title)
                .textSelection(.enabled)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: typography.footnote))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

/// A one-line media failure notice rendered under the media content.
public struct MediaErrorLabel: View {
    let message: String

    @Environment(\.timelineTypography) private var typography

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.system(size: typography.footnote))
            .foregroundStyle(.red)
            .textSelection(.enabled)
    }
}

#Preview {
    VStack(alignment: .leading) {
        AttachmentRowView(
            icon: Image(systemName: "doc"),
            title: "quarterly-report.pdf",
            subtitle: "1.2 MB"
        )
        AttachmentRowView(icon: Image(systemName: "waveform"), title: "Voice message")
        MediaErrorLabel(message: "Failed to download")
    }
    .padding()
}
