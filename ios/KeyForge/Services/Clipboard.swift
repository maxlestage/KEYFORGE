import UIKit
import UniformTypeIdentifiers

/// Copies secrets so they stay on this device (no Universal Clipboard) and, if the
/// user wishes, disappear from the clipboard after a while.
enum ClipboardExpiry: Int, CaseIterable, Identifiable {
    case never = 0
    case seconds30 = 30
    case minute1 = 60
    case minutes2 = 120

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .never: "Jamais"
        case .seconds30: "30 s"
        case .minute1: "1 min"
        case .minutes2: "2 min"
        }
    }
}

enum Clipboard {
    @MainActor
    static func copy(_ text: String, expiry: ClipboardExpiry) {
        var options: [UIPasteboard.OptionsKey: Any] = [.localOnly: true]
        if expiry != .never {
            options[.expirationDate] = Date().addingTimeInterval(TimeInterval(expiry.rawValue))
        }
        UIPasteboard.general.setItems([[UTType.plainText.identifier: text]], options: options)
    }
}
