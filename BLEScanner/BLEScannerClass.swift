//
//  BLEScannerClass.swift
//  BLEScanner
//
//  Created by Christian Möller on 02.01.23.
//

import CoreBluetooth

/// UI-facing representation of a discovered BLE peripheral.
///
/// This is intentionally *not* a raw dump of CoreBluetooth data:
/// - We normalize/derive common fields (RSSI, lastSeen, connectable, txPower, manufacturer ID).
/// - We keep a readable `details` string for debugging, without making the main list noisy.
/// - `id` uses `CBPeripheral.identifier` so SwiftUI list identity stays stable.
struct DiscoveredPeripheral: Identifiable {
    let id: UUID
    var peripheral: CBPeripheral

    var name: String
    var rssi: Int
    var lastSeen: Date

    var isConnectable: Bool
    var txPower: Int?

    var manufacturerCompanyId: UInt16?
    var manufacturerName: String?
    var manufacturerDataHex: String?

    /// Multiline, human-readable details (optional UI disclosure).
    var details: String
}

private extension Data {
    /// Renders a `Data` blob as a lowercase hexadecimal string.
    ///
    /// We use this for manufacturer data so it can be copied and pasted into external tools.
    func hexString(separator: String = "") -> String {
        map { String(format: "%02x", $0) }.joined(separator: separator)
    }
}

private enum Manufacturer {
    /// Minimal Bluetooth SIG “Company Identifier” mapping.
    ///
    /// This project intentionally keeps the mapping small. Add more entries as needed.
    static func name(for companyId: UInt16) -> String? {
        switch companyId {
        case 0x004C:
            return "Apple"
        default:
            return nil
        }
    }
}

class BluetoothScanner: NSObject, CBCentralManagerDelegate, ObservableObject {
    @Published var discoveredPeripherals = [DiscoveredPeripheral]()
    @Published var isScanning = false
    var centralManager: CBCentralManager!

    /// UUIDs of peripherals that have been discovered.
    ///
    /// We keep a separate set to prevent duplicates and to avoid relying on CBPeripheral hashing.
    private var discoveredPeripheralIds = Set<UUID>()

    /// Throttling state to keep SwiftUI updates/taps stable while scanning.
    ///
    /// CoreBluetooth can call `didDiscover` very frequently. If we publish changes on every
    /// callback, SwiftUI will constantly re-render rows, which can make taps (e.g. expanding
    /// “Details”) feel unreliable. We therefore limit UI updates per peripheral.
    private var lastUiUpdateById: [UUID: Date] = [:]

    /// Minimum interval between UI updates per device.
    ///
    /// A value around ~0.5–1.0s works well for “live” feel without jitter.
    private let uiUpdateInterval: TimeInterval = 0.75
    var timer: Timer?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        if centralManager.state == .poweredOn {
            // Start a fresh session.
            isScanning = true
            discoveredPeripherals.removeAll()
            discoveredPeripheralIds.removeAll()
            lastUiUpdateById.removeAll()

            // Start scanning for all peripherals.
            // If you want to scan for a subset, pass service UUIDs via `withServices`.
            centralManager.scanForPeripherals(withServices: nil)

            // Periodically restart the scan.
            // In practice this can help to keep discovery “fresh” on some devices/OS versions.
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                self?.centralManager.stopScan()
                self?.centralManager.scanForPeripherals(withServices: nil)
            }
        }
    }

    func stopScan() {
        // Set isScanning to false and stop the timer
        isScanning = false
        timer?.invalidate()
        centralManager.stopScan()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            //print("central.state is .unknown")
            stopScan()
        case .resetting:
            //print("central.state is .resetting")
            stopScan()
        case .unsupported:
            //print("central.state is .unsupported")
            stopScan()
        case .unauthorized:
            //print("central.state is .unauthorized")
            stopScan()
        case .poweredOff:
            //print("central.state is .poweredOff")
            stopScan()
        case .poweredOn:
            //print("central.state is .poweredOn")
            startScan()
        @unknown default:
            print("central.state is unknown")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Every callback represents a new “sighting” of the peripheral.
        // We treat this as the source-of-truth for `lastSeen` and RSSI.
        let now = Date()
        let rssiValue = RSSI.intValue

        // Connectable flag can appear under the official key or (on some Apple stacks)
        // under a private compatibility key.
        let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? Bool)
            ?? (advertisementData["KCBAdvDatalsConnectable"] as? NSNumber)?.boolValue
            ?? false

        // Tx Power can be `Int` or `NSNumber` depending on the platform.
        let txPower = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? Int
            ?? (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue

        // Manufacturer data starts with a 16-bit Bluetooth SIG company identifier (little-endian).
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let manufacturerCompanyId: UInt16? = {
            guard let manufacturerData, manufacturerData.count >= 2 else { return nil }
            // CoreBluetooth uses little-endian for the Bluetooth SIG Company Identifier.
            return UInt16(manufacturerData[0]) | (UInt16(manufacturerData[1]) << 8)
        }()
        let manufacturerName = manufacturerCompanyId.flatMap { Manufacturer.name(for: $0) }
        let manufacturerHex = manufacturerData?.hexString(separator: " ")

        // Prefer the peripheral’s advertised name; fall back to a stable placeholder.
        let name = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (name?.isEmpty == false) ? name! : "Unknown Device"

        // Build a readable (developer-oriented) details string.
        // This is used in the UI “Details” section as a convenient debug dump.
        let detailsLines: [String] = (
            advertisementData
                .map { key, value in "\(key): \(value)" }
                .sorted()
        )
        let detailsHeader: [String] = [
            "RSSI: \(rssiValue) dBm",
            "Last seen: \(now)",
            "Connectable: \(isConnectable ? "yes" : "no")"
        ] + (txPower.map { ["Tx Power: \($0)"] } ?? [])
        let details = (detailsHeader + detailsLines).joined(separator: "\n")

        let id = peripheral.identifier

        if !discoveredPeripheralIds.contains(id) {
            // First time we see this peripheral during the current scan session.
            discoveredPeripherals.append(
                DiscoveredPeripheral(
                    id: id,
                    peripheral: peripheral,
                    name: displayName,
                    rssi: rssiValue,
                    lastSeen: now,
                    isConnectable: isConnectable,
                    txPower: txPower,
                    manufacturerCompanyId: manufacturerCompanyId,
                    manufacturerName: manufacturerName,
                    manufacturerDataHex: manufacturerHex,
                    details: details
                )
            )
            discoveredPeripheralIds.insert(id)
            lastUiUpdateById[id] = now
        } else if let index = discoveredPeripherals.firstIndex(where: { $0.id == id }) {
            let previous = discoveredPeripherals[index]

            let lastUpdate = lastUiUpdateById[id] ?? .distantPast
            let isDue = now.timeIntervalSince(lastUpdate) >= uiUpdateInterval

            // Treat very small RSSI changes as noise.
            let rssiChangedSignificantly = abs(previous.rssi - rssiValue) >= 3
            let connectableChanged = previous.isConnectable != isConnectable
            let manufacturerChanged = previous.manufacturerCompanyId != manufacturerCompanyId
                || previous.manufacturerDataHex != manufacturerHex
            let txPowerChanged = previous.txPower != txPower
            let nameChanged = previous.name != displayName

            // Update UI model only when needed to keep the list stable/tappable.
            if isDue || rssiChangedSignificantly || connectableChanged || manufacturerChanged || txPowerChanged || nameChanged {
                discoveredPeripherals[index].peripheral = peripheral
                discoveredPeripherals[index].name = displayName
                discoveredPeripherals[index].rssi = rssiValue
                discoveredPeripherals[index].lastSeen = now
                discoveredPeripherals[index].isConnectable = isConnectable
                discoveredPeripherals[index].txPower = txPower
                discoveredPeripherals[index].manufacturerCompanyId = manufacturerCompanyId
                discoveredPeripherals[index].manufacturerName = manufacturerName
                discoveredPeripherals[index].manufacturerDataHex = manufacturerHex
                discoveredPeripherals[index].details = details
                lastUiUpdateById[id] = now
            }
        }
    }
}
