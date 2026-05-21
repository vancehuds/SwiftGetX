import Foundation
import SwiftUI

enum L10n {
    static func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: AppResources.bundle, comment: "")
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }
}

extension String {
    var localized: String {
        L10n.string(self)
    }
}
