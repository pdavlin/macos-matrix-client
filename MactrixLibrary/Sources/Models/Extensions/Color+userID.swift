import SwiftUI

public extension Color {
    init(userID: String) {
        self.init(
            String(
                format: "Username%02d",
                userID.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 16 + 1
            )
        )
    }
}
