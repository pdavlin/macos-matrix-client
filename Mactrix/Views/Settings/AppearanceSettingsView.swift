import SwiftUI
import Tokens

struct AppearanceSettingsView: View {
    @AppStorage(TypographyToken.fontSizeStorageKey) var fontSize = TypographyToken.defaultBaseFontSize

    var body: some View {
        Form {
            Picker("Font size", selection: $fontSize) {
                ForEach(TypographyToken.minBaseFontSize ..< TypographyToken.maxBaseFontSize + 1) {
                    Text("\($0)")
                        .tag($0)
                }
            }
        }
    }
}
