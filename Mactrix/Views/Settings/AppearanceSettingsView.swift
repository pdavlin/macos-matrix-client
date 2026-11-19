import Models
import SwiftUI
import Tokens

struct AppearanceSettingsView: View {
    @AppStorage(TypographyToken.fontSizeStorageKey) var fontSize = TypographyToken.defaultBaseFontSize
    /// MATRIX-178: a song or album link on a service that is not Apple Music
    /// opens on song.link and shows the music link marker.
    @AppStorage(MusicLinkPreferences.storageKey) var marksMusicLinks = MusicLinkPreferences.defaultValue
    /// MATRIX-194: the bridge-network badge on sidebar chat avatars.
    @AppStorage(NetworkBadgePreferences.storageKey) var showsNetworkBadges = NetworkBadgePreferences.defaultValue
    /// MATRIX-201: a click on an X or Bluesky post link opens the post in a
    /// popover. Off, the link opens in the browser.
    @AppStorage(PostPeekPreferences.storageKey) var peeksPostLinks = PostPeekPreferences.defaultValue

    var body: some View {
        Form {
            Picker("Font size", selection: $fontSize) {
                ForEach(TypographyToken.minBaseFontSize ..< TypographyToken.maxBaseFontSize + 1) {
                    Text("\($0)")
                        .tag($0)
                }
            }
            Toggle("Open song and album links on song.link", isOn: $marksMusicLinks)
            Toggle("Show network badges", isOn: $showsNetworkBadges)
            Toggle("Peek X and Bluesky links", isOn: $peeksPostLinks)
        }
    }
}
