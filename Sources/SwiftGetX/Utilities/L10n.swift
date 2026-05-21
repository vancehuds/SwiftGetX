import Foundation
import SwiftUI

enum L10n {
    static func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: AppResources.localizationBundle, comment: "")
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let locale: Locale
        if let langCode = UserDefaults.standard.string(forKey: AppSettings.languageUserDefaultsKey),
           langCode != "system" {
            locale = Locale(identifier: langCode)
        } else {
            locale = Locale.current
        }
        return String(format: string(key), locale: locale, arguments: arguments)
    }
}

extension String {
    var localized: String {
        L10n.string(self)
    }
}
