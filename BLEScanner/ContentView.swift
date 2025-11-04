//
//  ContentView.swift
//  BLEScanner
//
//  Created by Christian Möller on 02.01.23.
//

import SwiftUI
import CoreBluetooth

struct DiscoveredPeripheral {
    var peripheral: CBPeripheral
    var advertisedData: String
}

struct ContentView: View {
    @State private var bluetoothManager = BluetoothManager()
    @State private var searchText = ""
    @State private var showSettings = false
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status bar
                statusBar

                // Reconnection warning banner
                if bluetoothManager.isReconnecting {
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(bluetoothManager: bluetoothManager)
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                switch newPhase {
                case .active:
                    bluetoothManager.appDidEnterForeground()
                case .background:
                    bluetoothManager.appDidEnterBackground()
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

                Text("Attempt \(bluetoothManager.reconnectionAttempt) of 5")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Stop") {
                bluetoothManager.stopReconnecting()
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

            Text(bluetoothManager.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if bluetoothManager.connectionState == .connected,
               let peripheral = bluetoothManager.connectedPeripheral {
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
        switch bluetoothManager.connectionState {
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
                isConnected: bluetoothManager.connectedPeripheral?.identifier == discoveredPeripheral.peripheral.identifier,
                connectionState: bluetoothManager.connectionState,
                onConnect: {
                    bluetoothManager.connect(to: discoveredPeripheral.peripheral)
                },
                onDisconnect: {
                    bluetoothManager.disconnect()
                },
                onSetAutoConnect: {
                    bluetoothManager.setAutoConnectDevice(discoveredPeripheral.peripheral)
                    bluetoothManager.autoConnectEnabled = true
                }
            )
        }
        .listStyle(.plain)
    }

    private var filteredPeripherals: [DiscoveredPeripheral] {
        if searchText.isEmpty {
            return bluetoothManager.discoveredPeripherals
        }
        return bluetoothManager.discoveredPeripherals.filter {
            $0.peripheral.name?.lowercased().contains(searchText.lowercased()) == true
        }
    }

    // MARK: - Bottom Controls
    private var bottomControls: some View {
        VStack(spacing: 12) {
            if bluetoothManager.connectionState == .connected {
                Button(action: {
                    bluetoothManager.disconnect()
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
                if bluetoothManager.isScanning {
                    bluetoothManager.stopScan()
                } else {
                    bluetoothManager.startScan()
                }
            }) {
                Text(bluetoothManager.isScanning ? "Stop Scanning" : "Scan for Devices")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(bluetoothManager.isScanning ? Color.red : Color.blue)
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
    var bluetoothManager: BluetoothManager

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable Auto-Connect", isOn: Binding(
                        get: { bluetoothManager.autoConnectEnabled },
                        set: { bluetoothManager.autoConnectEnabled = $0 }
                    ))

                    if bluetoothManager.autoConnectEnabled {
                        Toggle("Background Reconnection", isOn: Binding(
                            get: { bluetoothManager.allowBackgroundReconnection },
                            set: { bluetoothManager.allowBackgroundReconnection = $0 }
                        ))

                        Button("Clear Auto-Connect Device") {
                            bluetoothManager.clearAutoConnectDevice()
                        }
                        .foregroundStyle(.red)
                    }
                } header: {
                    Text("Auto-Connection")
                } footer: {
                    if bluetoothManager.autoConnectEnabled {
                        Text("Auto-connect will attempt up to 5 reconnections. Background reconnection allows retries even when the app is in the background (uses more battery).")
                    } else {
                        Text("When enabled, the app will automatically connect to your saved ESP32 device when it's discovered.")
                    }
                }

                Section {
                    TextField("Shortcut Name", text: Binding(
                        get: { bluetoothManager.shortcutName },
                        set: { bluetoothManager.shortcutName = $0 }
                    ))
                    .autocapitalization(.none)
                } header: {
                    Text("iOS Shortcuts")
                } footer: {
                    Text("Enter the exact name of the Shortcut you want to run when your ESP32 connects. The shortcut will be triggered automatically after connection.")
                }

                Section {
                    HStack {
                        Text("Connection State")
                        Spacer()
                        Text(connectionStateText)
                            .foregroundStyle(.secondary)
                    }

                    if let peripheral = bluetoothManager.connectedPeripheral {
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
        switch bluetoothManager.connectionState {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .disconnecting: return "Disconnecting..."
        }
    }
}
