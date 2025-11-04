//
//  BLEManager.swift
//  BLEScanner
//
//  Handles Bluetooth Low Energy connectivity and device management
//

import Foundation
import CoreBluetooth
import Observation

@Observable
class BLEManager: NSObject {
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
            UserDefaults.standard.set(autoConnectEnabled, forKey: UserDefaultsKeys.autoConnectEnabled)
            if !autoConnectEnabled {
                stopReconnecting()
            }
        }
    }

    var allowBackgroundReconnection: Bool {
        didSet {
            UserDefaults.standard.set(allowBackgroundReconnection, forKey: UserDefaultsKeys.allowBackgroundReconnection)
        }
    }

    // MARK: - Private Properties
    private var centralManager: CBCentralManager!
    private var discoveredPeripheralSet = Set<CBPeripheral>()
    private var scanTimer: Timer?
    private var reconnectionTimer: Timer?
    private var connectionTimeoutTimer: Timer?

    // Reconnection state
    private var reconnectionDelay: TimeInterval = BLEConfiguration.initialReconnectionDelay

    // App lifecycle
    var isAppInForeground: Bool = true

    // Target device for auto-connect
    private var targetDeviceUUID: UUID? {
        didSet {
            if let uuid = targetDeviceUUID {
                UserDefaults.standard.set(uuid.uuidString, forKey: UserDefaultsKeys.autoConnectDeviceUUID)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.autoConnectDeviceUUID)
            }
        }
    }

    // Managers
    let notificationManager: NotificationManager
    let shortcutManager: ShortcutManager

    // MARK: - Initialization
    init(notificationManager: NotificationManager, shortcutManager: ShortcutManager) {
        self.notificationManager = notificationManager
        self.shortcutManager = shortcutManager

        // Load saved preferences
        self.autoConnectEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoConnectEnabled)
        self.allowBackgroundReconnection = UserDefaults.standard.bool(forKey: UserDefaultsKeys.allowBackgroundReconnection)

        if let uuidString = UserDefaults.standard.string(forKey: UserDefaultsKeys.autoConnectDeviceUUID),
           let uuid = UUID(uuidString: uuidString) {
            self.targetDeviceUUID = uuid
        }

        super.init()

        // Initialize CoreBluetooth with state restoration
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: BLEConfiguration.restoreIdentifierKey]
        )
    }

    // MARK: - Lifecycle Management
    func appDidEnterForeground() {
        isAppInForeground = true
        shortcutManager.appDidEnterForeground()

        // Update connection state in UserDefaults based on actual state
        if connectionState == .connected, let deviceName = connectedPeripheral?.name {
            UserDefaults.standard.set(true, forKey: "ESP32IsConnected")
            UserDefaults.standard.set(deviceName, forKey: "ESP32DeviceName")
        } else {
            UserDefaults.standard.set(false, forKey: "ESP32IsConnected")
        }

        // Reset reconnection attempts when app returns to foreground
        if isReconnecting && reconnectionAttempt >= BLEConfiguration.maxReconnectionAttempts {
            reconnectionAttempt = 0
            reconnectionDelay = BLEConfiguration.initialReconnectionDelay
        }
    }

    func appDidEnterBackground() {
        isAppInForeground = false
        shortcutManager.appDidEnterBackground()

        // Stop aggressive reconnection in background if not allowed
        if !allowBackgroundReconnection {
            stopReconnecting()
        }
    }

    func appWillTerminate() {
        stopReconnecting()
        stopScan()

        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    // MARK: - Scanning
    func startScan() {
        guard centralManager.state == .poweredOn else { return }

        isScanning = true
        discoveredPeripherals.removeAll()
        discoveredPeripheralSet.removeAll()

        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        // Periodic refresh for RSSI updates
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: BLEConfiguration.scanRefreshInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.centralManager.stopScan()
            self.centralManager.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        }
    }

    func stopScan() {
        isScanning = false
        scanTimer?.invalidate()
        centralManager.stopScan()
    }

    // MARK: - Connection
    func connect(to peripheral: CBPeripheral) {
        guard centralManager.state == .poweredOn else {
            statusMessage = "Bluetooth not ready"
            return
        }

        connectionTimeoutTimer?.invalidate()

        statusMessage = "Connecting to \(peripheral.name ?? "device")..."
        connectionState = .connecting
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)

        // Start timeout timer
        connectionTimeoutTimer = Timer.scheduledTimer(
            withTimeInterval: BLEConfiguration.connectionTimeout,
            repeats: false
        ) { [weak self] _ in
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
        stopReconnecting()
        centralManager.cancelPeripheralConnection(peripheral)
    }

    // MARK: - Auto-Connect
    func setAutoConnectDevice(_ peripheral: CBPeripheral) {
        targetDeviceUUID = peripheral.identifier
        reconnectionAttempt = 0
        reconnectionDelay = BLEConfiguration.initialReconnectionDelay
        statusMessage = "Auto-connect enabled for \(peripheral.name ?? "device")"
    }

    func clearAutoConnectDevice() {
        targetDeviceUUID = nil
        stopReconnecting()
        statusMessage = "Auto-connect disabled"
    }

    // MARK: - Reconnection Logic
    func stopReconnecting() {
        let wasReconnecting = isReconnecting
        isReconnecting = false
        reconnectionTimer?.invalidate()
        reconnectionTimer = nil
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil

        if wasReconnecting {
            statusMessage = "Stopped reconnecting"
        }
    }

    private func scheduleReconnection(to peripheral: CBPeripheral) {
        guard autoConnectEnabled,
              targetDeviceUUID == peripheral.identifier,
              reconnectionAttempt < BLEConfiguration.maxReconnectionAttempts else {
            if reconnectionAttempt >= BLEConfiguration.maxReconnectionAttempts {
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

        let delay = min(
            reconnectionDelay * Double(reconnectionAttempt),
            BLEConfiguration.maxReconnectionDelay
        )
        statusMessage = "Reconnecting in \(Int(delay))s (attempt \(reconnectionAttempt)/\(BLEConfiguration.maxReconnectionAttempts))"

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
        // Exponential backoff
        reconnectionDelay = min(reconnectionDelay * 1.5, BLEConfiguration.maxReconnectionDelay)
        scheduleReconnection(to: peripheral)
    }

    private func resetReconnectionState() {
        reconnectionAttempt = 0
        reconnectionDelay = BLEConfiguration.initialReconnectionDelay
        isReconnecting = false
        reconnectionTimer?.invalidate()
        reconnectionTimer = nil
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
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
        var advertisedData = advertisementData
            .map { "\($0): \($1)" }
            .sorted(by: { $0 < $1 })
            .joined(separator: "\n")

        // Add timestamp and RSSI
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
        connectionTimeoutTimer?.invalidate()

        connectionState = .connected
        connectedPeripheral = peripheral
        let deviceName = peripheral.name ?? "device"
        statusMessage = "Connected to \(deviceName)"

        resetReconnectionState()

        // Store connection state for App Intent
        UserDefaults.standard.set(true, forKey: "ESP32IsConnected")
        UserDefaults.standard.set(deviceName, forKey: "ESP32DeviceName")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "ESP32LastConnectionTime")

        // Send notification
        notificationManager.sendConnectionNotification(deviceName: deviceName)

        // Discover services
        peripheral.discoverServices(nil)

        // Trigger shortcut (only in foreground)
        if isAppInForeground {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                let result = self.shortcutManager.runShortcut()
                self.statusMessage = result
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        connectedPeripheral = nil
        connectionTimeoutTimer?.invalidate()

        statusMessage = "Failed to connect: \(error?.localizedDescription ?? "Unknown error")"
        handleConnectionFailure(for: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        connectedPeripheral = nil

        // Update connection state for App Intent
        UserDefaults.standard.set(false, forKey: "ESP32IsConnected")

        if let error = error {
            // Unexpected disconnection
            statusMessage = "Disconnected: \(error.localizedDescription)"
            if autoConnectEnabled, targetDeviceUUID == peripheral.identifier {
                scheduleReconnection(to: peripheral)
            }
        } else {
            // User-initiated disconnection
            statusMessage = "Disconnected"
        }

        // Resume scanning if not reconnecting
        if !isScanning && !isReconnecting {
            startScan()
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
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
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            statusMessage = "Service discovery error: \(error.localizedDescription)"
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            statusMessage = "Characteristic discovery error: \(error.localizedDescription)"
            return
        }

        if let characteristics = service.characteristics {
            for characteristic in characteristics {
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
