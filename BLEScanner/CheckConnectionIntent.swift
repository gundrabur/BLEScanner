//
//  CheckConnectionIntent.swift
//  BLEScanner
//
//  App Intent for checking ESP32 connection status from Shortcuts
//

import AppIntents
import Foundation

// MARK: - Connection Status Entity
struct ConnectionStatus: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Connection Status")
    static var defaultQuery = ConnectionStatusQuery()

    var id: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(deviceName): \(isConnected ? "Connected" : "Disconnected")")
    }

    let deviceName: String
    let isConnected: Bool
    let lastUpdated: Date
}

// MARK: - Query
struct ConnectionStatusQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ConnectionStatus] {
        return []
    }

    func suggestedEntities() async throws -> [ConnectionStatus] {
        return []
    }
}

// MARK: - Check Connection Intent
@available(iOS 16.0, *)
struct CheckConnectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Check ESP32 Connection"
    static var description = IntentDescription("Check if your ESP32 device is currently connected")

    // Run in background without opening app
    static var openAppWhenRun: Bool = false

    // MARK: - Perform
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        // Read connection state from UserDefaults
        let isConnected = UserDefaults.standard.bool(forKey: "ESP32IsConnected")
        let deviceName = UserDefaults.standard.string(forKey: "ESP32DeviceName") ?? "ESP32"

        let dialog: String
        if isConnected {
            dialog = "\(deviceName) is connected"
        } else {
            dialog = "\(deviceName) is not connected"
        }

        return .result(
            value: isConnected,
            dialog: IntentDialog(stringLiteral: dialog)
        )
    }
}

// MARK: - Get Device Name Intent
@available(iOS 16.0, *)
struct GetDeviceNameIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Connected Device Name"
    static var description = IntentDescription("Get the name of the currently connected ESP32 device")

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let isConnected = UserDefaults.standard.bool(forKey: "ESP32IsConnected")
        let deviceName = UserDefaults.standard.string(forKey: "ESP32DeviceName") ?? "No device"

        if isConnected {
            return .result(
                value: deviceName,
                dialog: IntentDialog(stringLiteral: "Connected to \(deviceName)")
            )
        } else {
            return .result(
                value: "Not connected",
                dialog: IntentDialog(stringLiteral: "No device is connected")
            )
        }
    }
}

// MARK: - Get Last Connection Time Intent
@available(iOS 16.0, *)
struct GetLastConnectionTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Last Connection Time"
    static var description = IntentDescription("Get when ESP32 was last connected")

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let timestamp = UserDefaults.standard.double(forKey: "ESP32LastConnectionTime")

        if timestamp > 0 {
            let date = Date(timeIntervalSince1970: timestamp)
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relativeTime = formatter.localizedString(for: date, relativeTo: Date())

            return .result(
                value: relativeTime,
                dialog: IntentDialog(stringLiteral: "Last connected \(relativeTime)")
            )
        } else {
            return .result(
                value: "Never",
                dialog: IntentDialog(stringLiteral: "Device has never connected")
            )
        }
    }
}

// MARK: - App Shortcuts Provider
@available(iOS 16.0, *)
struct BLEScannerShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckConnectionIntent(),
            phrases: [
                "Check \(.applicationName) connection",
                "Is my ESP32 connected in \(.applicationName)",
                "Check BLE connection in \(.applicationName)"
            ],
            shortTitle: "Check Connection",
            systemImageName: "antenna.radiowaves.left.and.right"
        )

        AppShortcut(
            intent: GetDeviceNameIntent(),
            phrases: [
                "Get device name in \(.applicationName)",
                "Which ESP32 is connected in \(.applicationName)"
            ],
            shortTitle: "Device Name",
            systemImageName: "tag.fill"
        )

        AppShortcut(
            intent: GetLastConnectionTimeIntent(),
            phrases: [
                "When did ESP32 connect in \(.applicationName)",
                "Last connection time in \(.applicationName)"
            ],
            shortTitle: "Last Connection",
            systemImageName: "clock.fill"
        )
    }
}
