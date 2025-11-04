//
//  ContentView.swift
//  BLEScanner
//
//  Created by Christian Möller on 02.01.23.
//

import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @State private var notificationManager = NotificationManager()
    @State private var shortcutManager = ShortcutManager()
    @State private var bleManager: BLEManager
    @State private var searchText = ""
    @State private var showSettings = false
    @State private var showAutomationGuide = false
    @Environment(\.scenePhase) var scenePhase

    init() {
        let notifManager = NotificationManager()
        let shortManager = ShortcutManager()
        _notificationManager = State(initialValue: notifManager)
        _shortcutManager = State(initialValue: shortManager)
        _bleManager = State(initialValue: BLEManager(
            notificationManager: notifManager,
            shortcutManager: shortManager
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status bar
                statusBar

                // Reconnection warning banner
                if bleManager.isReconnecting {
                    reconnectionBanner
                }

                // Search bar
                searchBar

                // Device list
                deviceList

                // Bottom controls
                bottomControls
            }
            .navigationTitle("BLE Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showAutomationGuide = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    bleManager: bleManager,
                    notificationManager: notificationManager,
                    shortcutManager: shortcutManager
                )
            }
            .sheet(isPresented: $showAutomationGuide) {
                AutomationGuideView()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                switch newPhase {
                case .active:
                    bleManager.appDidEnterForeground()
                case .background:
                    bleManager.appDidEnterBackground()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    // MARK: - Reconnection Banner
    private var reconnectionBanner: some View {
        HStack {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 4) {
                Text("Reconnecting...")
                    .font(.caption)
                    .fontWeight(.semibold)

                Text("Attempt \(bleManager.reconnectionAttempt) of \(BLEConfiguration.maxReconnectionAttempts)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Stop") {
                bleManager.stopReconnecting()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }
        .padding()
        .background(Color.orange.opacity(0.2))
    }

    // MARK: - Status Bar
    private var statusBar: some View {
        HStack {
            Circle()
                .fill(connectionStatusColor)
                .frame(width: 10, height: 10)

            Text(bleManager.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if bleManager.connectionState == .connected,
               let peripheral = bleManager.connectedPeripheral {
                Text(peripheral.name ?? "Unknown")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }

    private var connectionStatusColor: Color {
        switch bleManager.connectionState {
        case .disconnected:
            return .gray
        case .connecting, .disconnecting:
            return .orange
        case .connected:
            return .green
        }
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack {
            TextField("Search devices", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    // MARK: - Device List
    private var deviceList: some View {
        List(filteredPeripherals, id: \.peripheral.identifier) { discoveredPeripheral in
            DeviceRow(
                peripheral: discoveredPeripheral.peripheral,
                advertisedData: discoveredPeripheral.advertisedData,
                isConnected: bleManager.connectedPeripheral?.identifier == discoveredPeripheral.peripheral.identifier,
                connectionState: bleManager.connectionState,
                onConnect: {
                    bleManager.connect(to: discoveredPeripheral.peripheral)
                },
                onDisconnect: {
                    bleManager.disconnect()
                },
                onSetAutoConnect: {
                    bleManager.setAutoConnectDevice(discoveredPeripheral.peripheral)
                    bleManager.autoConnectEnabled = true
                }
            )
        }
        .listStyle(.plain)
    }

    private var filteredPeripherals: [DiscoveredPeripheral] {
        if searchText.isEmpty {
            return bleManager.discoveredPeripherals
        }
        return bleManager.discoveredPeripherals.filter {
            $0.peripheral.name?.lowercased().contains(searchText.lowercased()) == true
        }
    }

    // MARK: - Bottom Controls
    private var bottomControls: some View {
        VStack(spacing: 12) {
            if bleManager.connectionState == .connected {
                Button(action: {
                    bleManager.disconnect()
                }) {
                    Text("Disconnect")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .cornerRadius(10)
                }
            }

            Button(action: {
                if bleManager.isScanning {
                    bleManager.stopScan()
                } else {
                    bleManager.startScan()
                }
            }) {
                Text(bleManager.isScanning ? "Stop Scanning" : "Scan for Devices")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(bleManager.isScanning ? Color.red : Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}

// MARK: - Device Row
struct DeviceRow: View {
    let peripheral: CBPeripheral
    let advertisedData: String
    let isConnected: Bool
    let connectionState: ConnectionState
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onSetAutoConnect: () -> Void

    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(peripheral.name ?? "Unknown Device")
                        .font(.headline)

                    Text(peripheral.identifier.uuidString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if showDetails {
                Text(advertisedData)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .padding(.vertical, 4)
            }

            HStack(spacing: 8) {
                Button(action: {
                    showDetails.toggle()
                }) {
                    Label(showDetails ? "Hide Details" : "Show Details", systemImage: showDetails ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if !isConnected && connectionState == .disconnected {
                    Button(action: onConnect) {
                        Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button(action: onSetAutoConnect) {
                        Label("Auto", systemImage: "bolt.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if isConnected {
                    Button(action: onDisconnect) {
                        Label("Disconnect", systemImage: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    var bleManager: BLEManager
    var notificationManager: NotificationManager
    var shortcutManager: ShortcutManager

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable Auto-Connect", isOn: Binding(
                        get: { bleManager.autoConnectEnabled },
                        set: { bleManager.autoConnectEnabled = $0 }
                    ))

                    if bleManager.autoConnectEnabled {
                        Toggle("Background Reconnection", isOn: Binding(
                            get: { bleManager.allowBackgroundReconnection },
                            set: { bleManager.allowBackgroundReconnection = $0 }
                        ))

                        Button("Clear Auto-Connect Device") {
                            bleManager.clearAutoConnectDevice()
                        }
                        .foregroundStyle(.red)
                    }
                } header: {
                    Text("Auto-Connection")
                } footer: {
                    if bleManager.autoConnectEnabled {
                        Text("Auto-connect will attempt up to \(BLEConfiguration.maxReconnectionAttempts) reconnections. Background reconnection allows retries even when the app is in the background (uses more battery).")
                    } else {
                        Text("When enabled, the app will automatically connect to your saved ESP32 device when it's discovered.")
                    }
                }

                Section {
                    Toggle("Send Notifications", isOn: Binding(
                        get: { notificationManager.notificationsEnabled },
                        set: { notificationManager.notificationsEnabled = $0 }
                    ))
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Receive notifications when your ESP32 connects. Use this with Shortcuts automation to trigger actions even when the app is in the background.")
                }

                Section {
                    TextField("Shortcut Name", text: Binding(
                        get: { shortcutManager.shortcutName },
                        set: { shortcutManager.shortcutName = $0 }
                    ))
                    .autocapitalization(.none)
                } header: {
                    Text("iOS Shortcuts (Foreground Only)")
                } footer: {
                    Text("This shortcut runs only when the app is in the foreground. For background automation, enable notifications above and create a Shortcuts automation triggered by the 'ESP32 Connected' notification.")
                }

                Section {
                    HStack {
                        Text("Connection State")
                        Spacer()
                        Text(connectionStateText)
                            .foregroundStyle(.secondary)
                    }

                    if let peripheral = bleManager.connectedPeripheral {
                        HStack {
                            Text("Connected Device")
                            Spacer()
                            Text(peripheral.name ?? "Unknown")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Status")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var connectionStateText: String {
        switch bleManager.connectionState {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .disconnecting: return "Disconnecting..."
        }
    }
}
