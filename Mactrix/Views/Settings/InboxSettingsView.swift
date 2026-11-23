import Models
import SwiftUI

/// Settings > Inbox (MATRIX-222): the inbox flow.
struct InboxSettingsView: View {
    /// After Archive, Snooze, or Mark as Read on the open chat, the next
    /// chat of the list opens. On by default, as in Beeper.
    @AppStorage(InboxFlowPreferences.storageKey) var opensNextChat = InboxFlowPreferences.defaultValue

    var body: some View {
        Form {
            Toggle("After Archive, Snooze or Mark Read, open the next chat", isOn: $opensNextChat)
        }
    }
}
