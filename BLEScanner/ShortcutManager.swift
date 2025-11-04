//
//  ShortcutManager.swift
//  BLEScanner
//
//  Handles iOS Shortcuts integration
//

import Foundation
import UIKit

@Observable
class ShortcutManager {
    var shortcutName: String {
        didSet {
            UserDefaults.standard.set(shortcutName, forKey: UserDefaultsKeys.shortcutName)
        }
    }

    var isAppInForeground: Bool = true

    init() {
        self.shortcutName = UserDefaults.standard.string(forKey: UserDefaultsKeys.shortcutName) ?? ""
    }

    // MARK: - Run Shortcut
    func runShortcut() -> String {
        guard !shortcutName.isEmpty else {
            return "No shortcut configured"
        }

        // Only run in foreground
        guard isAppInForeground else {
            return "Shortcut will run when app is in foreground"
        }

        // URL encode the shortcut name
        guard let encodedName = shortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "shortcuts://run-shortcut?name=\(encodedName)") else {
            return "Invalid shortcut name"
        }

        #if os(iOS)
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:]) { success in
                DispatchQueue.main.async {
                    if success {
                        print("✅ Shortcut '\(self.shortcutName)' triggered")
                    } else {
                        print("❌ Failed to run shortcut")
                    }
                }
            }
            return "Shortcut '\(shortcutName)' triggered"
        } else {
            return "Shortcuts app not available"
        }
        #else
        return "Shortcuts only available on iOS"
        #endif
    }

    // MARK: - Lifecycle
    func appDidEnterForeground() {
        isAppInForeground = true
    }

    func appDidEnterBackground() {
        isAppInForeground = false
    }
}
