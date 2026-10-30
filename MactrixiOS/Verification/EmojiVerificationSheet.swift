import Models
import SwiftUI

/// The SAS comparison sheet for iPhone and iPad.
///
/// The shared `SessionVerificationModal` puts all seven emojis in one row,
/// which is wider than an iPhone screen. This sheet shows the same data in a
/// grid. The question and the two answers are the same as on the Mac.
struct EmojiVerificationSheet<Emoji: SessionVerificationEmoji>: View {
    let data: SessionVerificationData<Emoji>
    let onAnswer: (_ match: Bool) -> Void

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    private var question: String {
        switch data {
        case .emojis:
            "Do the emojis match the other device?"
        case .decimals:
            "Do the numbers match the other device?"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text(question)
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    comparison

                    Text("Compare these with the other device. Confirm only if they are the same and in the same order.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .navigationTitle("Verify Session")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        onAnswer(true)
                    } label: {
                        Text("They match").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("verificationMatch")

                    Button(role: .destructive) {
                        onAnswer(false)
                    } label: {
                        Text("They do not match").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .accessibilityIdentifier("verificationNoMatch")
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private var comparison: some View {
        switch data {
        case let .emojis(emojis, _):
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(emojis) { emoji in
                    VStack(spacing: 4) {
                        Text(emoji.symbol)
                            .font(.system(size: 40))
                        Text(emoji.description)
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        case let .decimals(values):
            HStack(spacing: 16) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Text(String(value))
                        .font(.title.monospacedDigit())
                }
            }
        }
    }
}

#Preview {
    EmojiVerificationSheet(
        data: SessionVerificationData.emojis(emojis: [
            MockSessionVerificationEmoji(description: "Dog", symbol: "🐶"),
            MockSessionVerificationEmoji(description: "Rocket", symbol: "🚀"),
            MockSessionVerificationEmoji(description: "Fish", symbol: "🐠"),
            MockSessionVerificationEmoji(description: "Butterfly", symbol: "🦋"),
            MockSessionVerificationEmoji(description: "Rose", symbol: "🌹"),
            MockSessionVerificationEmoji(description: "Sun", symbol: "☀️"),
            MockSessionVerificationEmoji(description: "Telephone", symbol: "☎️"),
        ], indices: Data()),
        onAnswer: { _ in }
    )
}
