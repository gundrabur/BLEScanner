//
//  BLEScannerClass.swift
//  BLEScanner
//
//  Created by Christian Möller on 02.01.23.
//

import Foundation
import CoreBluetooth
import Observation
import UIKit
import UserNotifications

// MARK: - Connection State Enum
enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case disconnecting
}

// MARK: - Bluetooth Manager
@Observable
class BluetoothManager: NSObject {
    // MARK: - Observable Properties
    var discoveredPeripherals = [DiscoveredPeripheral]()
    var isScanning = false
    var connectionState: ConnectionState = .disconnected
    var connectedPeripheral: CBPeripheral?
    var statusMessage: String = "Ready"
    var isReconnecting: Bool = false
    var reconnectionAttempt: Int = 0
    var autoConnectEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoConnectEnabled, forKey: autoConnectEnabledKey)
            if !autoConnectEnabled {
                stopReconnecting()
            }
        }
    }
    var shortcutName: String {
        didSet {
            UserDefaults.standard.set(shortcutName, forKey: shortcutNameKey)
        }
    }

    // MARK: - Private Properties
    private var centralManager: CBCentralManager!
    private var discoveredPeripheralSet = Set<CBPeripheral>()
    private var timer: Timer?
    private var reconnectionTimer: Timer?
    private var connectionTimeoutTimer: Timer?

    // Reconnection configuration
    private let maxReconnectionAttempts = 5
    private let connectionTimeout: TimeInterval = 10.0
    private var reconnectionDelay: TimeInterval = 2.0
    private let maxReconnectionDelay: TimeInterval = 30.0

    // App lifecycle tracking
    var isAppInForeground: Bool = true
    var allowBackgroundReconnection: Bool {
        didSet {
            UserDefaults.standard.set(allowBackgroundReconnection, forKey: allowBackgroundReconnectionKey)
        }
    }

    // Persistence keys
    private let autoConnectDeviceKey = "AutoConnectDeviceUUID"
    private let autoConnectEnabledKey = "AutoConnectEnabled"
    private let shortcutNameKey = "ShortcutToRun"
    private let allowBackgroundReconnectionKey = "AllowBackgroundReconnection"

    private var targetDeviceUUID: UUID? {
        didSet {
            if let uuid = targetDeviceUUID {
                UserDefaults.standard.set(uuid.uuidString, forKey: autoConnectDeviceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: autoConnectDeviceKey)
            }
        }
    }

    // State restoration
    private let restoreIdentifierKey = "BLECentralManagerIdentifier"

    // MARK: - Initialization
    override init() {
        // Load saved preferences
        self.autoConnectEnabled = UserDefaults.standard.bool(forKey: autoConnectEnabledKey)
        self.shortcutName = UserDefaults.standard.string(forKey: shortcutNameKey) ?? ""
        self.allowBackgroundReconnection = UserDefaults.standard.bool(forKey: allowBackgroundReconnectionKey)

        if let uuidString = UserDefaults.standard.string(forKey: autoConnectDeviceKey),
           let uuid = UUID(uuidString: uuidString) {
            self.targetDeviceUUID = uuid
        }

        super.init()

        // Initialize with state restoration
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: restoreIdentifierKey]
        )
    }

    // MARK: - Lifecycle Management
    func appDidEnterForeground() {
        isAppInForeground = true
        // Reset reconnection attempts when app returns to foreground
        if isReconnecting && reconnectionAttempt >= maxReconnectionAttempts {
            reconnectionAttempt = 0
            reconnectionDelay = 2.0
        }
    }

    func appDidEnterBackground() {
        isAppInForeground = false
        // Stop aggressive reconnection in background
        if !allowBackgroundReconnection {
            stopReconnecting()
        }
    }

    func appWillTerminate() {
        // Clean up all timers and pending connections
        stopReconnecting()
        stopScan()
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    // MARK: - Scanning Methods
    func startScan() {
        guard centralManager.state == .poweredOn else { return }

        isScanning = true
        discoveredPeripherals.removeAll()
        discoveredPeripheralSet.removeAll()

        // Scan for all peripherals
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])

        // Periodic restart for RSSI updates
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.centralManager.stopScan()
            self.centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    func stopScan() {
        isScanning = false
        timer?.invalidate()
        centralManager.stopScan()
    }

    // MARK: - Connection Methods
    func connect(to peripheral: CBPeripheral) {
        guard centralManager.state == .poweredOn else {
            statusMessage = "Bluetooth not ready"
            return
        }

        // Cancel any existing connection attempts
        connectionTimeoutTimer?.invalidate()

        statusMessage = "Connecting to \(peripheral.name ?? "device")..."
        connectionState = .connecting
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)

        // Start connection timeout timer
        connectionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: connectionTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.connectionState == .connecting {
                self.statusMessage = "Connection timeout"
                self.centralManager.cancelPeripheralConnection(peripheral)
                self.connectionState = .disconnected
                self.handleConnectionFailure(for: peripheral)
            }
        }
    }

    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        statusMessage = "Disconnecting..."
        connectionState = .disconnecting
        stopReconnecting()  // Stop any reconnection attempts
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func setAutoConnectDevice(_ peripheral: CBPeripheral) {
        targetDeviceUUID = peripheral.identifier
        reconnectionAttempt = 0  // Reset attempts for new device
        reconnectionDelay = 2.0
        statusMessage = "Auto-connect enabled for \(peripheral.name ?? "device")"
    }

    func clearAutoConnectDevice() {
        targetDeviceUUID = nil
        stopReconnecting()
        statusMessage = "Auto-connect disabled"
    }

    func stopReconnecting() {
        isReconnecting = false
        reconnectionTimer?.invalidate()
        reconnectionTimer = nil
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil

        if isReconnecting {
            statusMessage = "Stopped reconnecting"
        }
    }

    // MARK: - Reconnection Logic
    private func scheduleReconnection(to peripheral: CBPeripheral) {
        guard autoConnectEnabled,
              targetDeviceUUID == peripheral.identifier,
              reconnectionAttempt < maxReconnectionAttempts else {
            if reconnectionAttempt >= maxReconnectionAttempts {
                statusMessage = "Max reconnection attempts reached. Tap to retry."
                isReconnecting = false
            }
            return
        }

        // Don't reconnect in background unless allowed
        guard isAppInForeground || allowBackgroundReconnection else {
            statusMessage = "Reconnection paused (app in background)"
            return
        }

        isReconnecting = true
        reconnectionAttempt += 1

        let delay = min(reconnectionDelay * Double(reconnectionAttempt), maxReconnectionDelay)
        statusMessage = "Reconnecting in \(Int(delay))s (attempt \(reconnectionAttempt)/\(maxReconnectionAttempts))"

        reconnectionTimer?.invalidate()
        reconnectionTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            guard self.centralManager.state == .poweredOn else {
                self.statusMessage = "Waiting for Bluetooth..."
                return
            }

            self.connect(to: peripheral)
        }
    }

    private func handleConnectionFailure(for peripheral: CBPeripheral) {
        // Increase delay with exponential backoff
        reconnectionDelay = min(reconnectionDelay * 1.5, maxReconnectionDelay)
        scheduleReconnection(to: peripheral)
    }

    private func resetReconnectionState() {
        reconnectionAttempt = 0
        reconnectionDelay = 2.0
        isReconnecting = false
        reconnectionTimer?.invalidate()
        reconnectionTimer = nil
    }

    // MARK: - Shortcuts Integration
    private func runShortcut() {
        guard !shortcutName.isEmpty else {
            statusMessage = "No shortcut configured"
            return
        }

        // URL encode the shortcut name
        guard let encodedName = shortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "shortcuts://run-shortcut?name=\(encodedName)") else {
            statusMessage = "Invalid shortcut name"
            return
        }

        #if os(iOS)
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:]) { [weak self] success in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if success {
                        self.statusMessage = "Shortcut '\(self.shortcutName)' triggered"
                    } else {
                        self.statusMessage = "Failed to run shortcut"
                    }
                }
            }
        } else {
            statusMessage = "Shortcuts app not available"
        }
        #else
        statusMessage = "Shortcuts only available on iOS"
        #endif
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown, .resetting, .unsupported, .unauthorized, .poweredOff:
            stopScan()
            statusMessage = "Bluetooth unavailable"
        case .poweredOn:
            statusMessage = "Bluetooth ready"
            startScan()

            // Attempt to reconnect to saved device
            if autoConnectEnabled, let uuid = targetDeviceUUID {
                let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
                if let peripheral = peripherals.first {
                    connect(to: peripheral)
                }
            }
        @unknown default:
            statusMessage = "Unknown Bluetooth state"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Build advertised data string
        var advertisedData = advertisementData.map { "\($0): \($1)" }.sorted(by: { $0 < $1 }).joined(separator: "\n")

        // Add timestamp
        if let timestampValue = advertisementData["kCBAdvDataTimestamp"] as? Double {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss"
            let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: timestampValue))
            advertisedData = "actual rssi: \(RSSI) dB\n" + "Timestamp: \(dateString)\n" + advertisedData
        }

        // Update or add peripheral
        if !discoveredPeripheralSet.contains(peripheral) {
            discoveredPeripherals.append(DiscoveredPeripheral(peripheral: peripheral, advertisedData: advertisedData))
            discoveredPeripheralSet.insert(peripheral)
        } else {
            if let index = discoveredPeripherals.firstIndex(where: { $0.peripheral == peripheral }) {
                discoveredPeripherals[index].advertisedData = advertisedData
            }
        }

        // Auto-connect logic
        if autoConnectEnabled,
           connectionState == .disconnected,
           let targetUUID = targetDeviceUUID,
           peripheral.identifier == targetUUID {
            stopScan()
            connect(to: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Cancel timeout timer
        connectionTimeoutTimer?.invalidate()

        connectionState = .connected
        connectedPeripheral = peripheral
        statusMessage = "Connected to \(peripheral.name ?? "device")"

        // Reset reconnection state on successful connection
        resetReconnectionState()

        // Discover services
        peripheral.discoverServices(nil)

        // Trigger shortcut after connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.runShortcut()
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        connectedPeripheral = nil
        connectionTimeoutTimer?.invalidate()

        statusMessage = "Failed to connect: \(error?.localizedDescription ?? "Unknown error")"

        // Use new reconnection logic with limits and backoff
        handleConnectionFailure(for: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        connectedPeripheral = nil

        if let error = error {
            statusMessage = "Disconnected: \(error.localizedDescription)"
            // Unexpected disconnection - try to reconnect
            if autoConnectEnabled, targetDeviceUUID == peripheral.identifier {
                scheduleReconnection(to: peripheral)
            }
        } else {
            statusMessage = "Disconnected"
            // User-initiated disconnection - don't reconnect
        }

        // Resume scanning if not reconnecting
        if !isScanning && !isReconnecting {
            startScan()
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        // Handle state restoration for background operation
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                peripheral.delegate = self
                if peripheral.state == .connected {
                    connectedPeripheral = peripheral
                    connectionState = .connected
                    statusMessage = "Reconnected to \(peripheral.name ?? "device")"
                }
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            statusMessage = "Service discovery error: \(error.localizedDescription)"
            return
        }

        guard let services = peripheral.services else { return }

        // Discover characteristics for each service
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            statusMessage = "Characteristic discovery error: \(error.localizedDescription)"
            return
        }

        // Here you can subscribe to notifications or read/write characteristics
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                // Enable notifications if the characteristic supports it
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            statusMessage = "Read error: \(error.localizedDescription)"
            return
        }

        // Handle characteristic value updates here
        // This is where you'd process data from your ESP32
    }
}
