import Models
import SwiftUI
import Tokens

struct MessageReactionToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(
            action: { configuration.isOn.toggle() },
            label: {
                configuration.label
                    .background(
                        configuration.isOn ?
                            Color.blue.quaternary : Color.gray.quaternary
                    )
            }
        )
        .buttonStyle(.plain)
        .overlay {
            RoundedRectangle(cornerRadius: BubbleToken.cornerRadius)
                .stroke(configuration.isOn ? Color.blue : Color.gray)
        }
    }
}

public struct MessageReactionView<Reaction: Models.Reaction>: View {
    let reaction: Reaction
    let active: Binding<Bool>

    @FocusState private var isFocused: Bool

    public init(reaction: Reaction, active: Binding<Bool>) {
        self.reaction = reaction
        self.active = active
    }

    var helpText: String {
        let sendersString = reaction.senders.prefix(5)
            .map(\.senderId)
            .joined(separator: ", ")

        return "Reacted by \(sendersString)"
    }

    public var body: some View {
        Toggle(isOn: active, label: {
            HStack(spacing: 0) {
                Text(reaction.key)
                Text("\(reaction.senders.count)")
                    .padding(.horizontal, DensityToken.reactionCountPadding)
            }
            .padding(DensityToken.reactionPadding)
        })
        .toggleStyle(MessageReactionToggleStyle())
        .help(helpText)
    }
}

#Preview {
    @Previewable @State var active = false
    MessageReactionView(reaction: MockReaction(), active: $active)
        .padding()
}
