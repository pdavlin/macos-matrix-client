import SwiftUI
import Tokens

/// The bar above the composer text field in edit mode (MATRIX-109, M2-B2):
/// a pencil, "Editing message", a one-line preview of the original text,
/// and a cancel button.
///
/// The view only draws the bar and reports the cancel. The composer owns edit
/// mode: the x button and Esc in the text field both cancel it.
public struct ComposerEditBar: View {
    let previewText: String
    let onCancel: () -> Void

    /// - Parameters:
    ///   - previewText: The original text on one line
    ///     (`Models.ComposerEdit.previewText(fromDraftText:)`). An empty
    ///     text, for example a media message with no caption, shows no
    ///     preview line.
    ///   - onCancel: Called when the x button is clicked.
    public init(previewText: String, onCancel: @escaping () -> Void) {
        self.previewText = previewText
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "pencil")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Editing message")
                    .bold()
                if !previewText.isEmpty {
                    Text(previewText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel editing")
            .accessibilityLabel(Text("Cancel editing"))
        }
        .padding(.horizontal, DensityToken.rowHorizontalPadding)
        .padding(.vertical, DensityToken.rowVerticalPadding)
        .padding(.top, DensityToken.rowVerticalPadding)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ComposerEditBar(previewText: "The original message text", onCancel: {})
        .frame(width: 400)
}
