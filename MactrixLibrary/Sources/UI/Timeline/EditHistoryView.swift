import Models
import SwiftUI

/// The edit history of one message (MATRIX-209): the content of the popover
/// that "Show Edit History" and a click on the "(edited)" mark open.
///
/// Each version shows its time, newest first, and the original has a mark.
/// A long version wraps. Past `maxListHeight` the list scrolls. A version
/// the crypto layer could not decrypt shows the unable-to-decrypt text.
///
/// The view is generic over the message content: the app passes the SDK's
/// content and draws each body with the timeline's text rendering.
public struct EditHistoryView<Message, MessageBody: View>: View {
    static var width: CGFloat {
        380
    }

    static var maxListHeight: CGFloat {
        420
    }

    let state: EditHistoryState<Message>
    let timeText: (Date) -> String
    let messageBody: (Message) -> MessageBody

    /// - Parameters:
    ///   - state: The versions, or the load state.
    ///   - timeText: A version's time as the list shows it. Date and time by
    ///     default; snapshot tests pass fixed text.
    ///   - messageBody: Draws one version's message body.
    public init(
        state: EditHistoryState<Message>,
        timeText: @escaping (Date) -> String = { $0.formatted(date: .abbreviated, time: .shortened) },
        @ViewBuilder messageBody: @escaping (Message) -> MessageBody
    ) {
        self.state = state
        self.timeText = timeText
        self.messageBody = messageBody
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit History")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()
            content
        }
        .frame(width: Self.width, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(16)
        case .failed:
            note("The edit history did not load.")
        case let .loaded(versions) where versions.isEmpty:
            note("No versions to show.")
        case let .loaded(versions):
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(versions) { version in
                        if version.id != versions.first?.id {
                            Divider()
                                .padding(.horizontal, 14)
                        }
                        row(version)
                    }
                }
            }
            .frame(maxHeight: Self.maxListHeight)
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }

    private func row(_ version: EditHistoryVersion<Message>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(version.date.map(timeText) ?? String(localized: "Unknown time"))
                if version.isOriginal {
                    Text("Original")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            switch version.body {
            case let .message(message):
                messageBody(message)
            case let .unableToDecrypt(cause):
                UnableToDecryptView(cause: cause)
            case let .other(description):
                Text(description)
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
