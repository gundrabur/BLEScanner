//
//  ContentView.swift
//  BLEScanner
//
//  Created by Christian Möller on 02.01.23.
//

import SwiftUI
import CoreBluetooth

/// Small signal-strength visualization used in each list row.
///
/// - Note: RSSI is measured in dBm (typically a negative number). We map the raw value
///   into a few coarse “human friendly” buckets to avoid jitter and to keep it readable.
private struct RSSIBarsView: View {
    let rssi: Int

    private var level: Int {
        // Rough, human-friendly buckets.
        // The values here are intentionally coarse to reduce “visual flicker” during live updates.
        switch rssi {
        case ..<(-90): return 0
        case ..<(-80): return 1
        case ..<(-70): return 2
        case ..<(-60): return 3
        default: return 4
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: 4, height: CGFloat(4 + index * 3))
                    .foregroundStyle(index < level ? .primary : .secondary)
                    .opacity(index < level ? 1 : 0.35)
            }
        }
        .accessibilityLabel("Signal strength")
        .accessibilityValue("\(rssi) dBm")
    }
}

/// A single device row.
///
/// This view intentionally keeps interaction state (`isExpanded`) outside of the row itself.
/// When scanning, the underlying model updates frequently. Storing expansion state in the
/// parent view avoids losing state during list diffing/re-rendering.
private struct PeripheralRowView: View {
    let device: DiscoveredPeripheral
    @Binding var isExpanded: Bool

    private var manufacturerLine: String {
        if let name = device.manufacturerName, let id = device.manufacturerCompanyId {
            return "\(name) · 0x\(String(format: "%04X", id))"
        }
        if let id = device.manufacturerCompanyId {
            return "0x\(String(format: "%04X", id))"
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.headline)

                    HStack(spacing: 8) {
                        if !manufacturerLine.isEmpty {
                            Text(manufacturerLine)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(device.lastSeen, style: .relative)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        RSSIBarsView(rssi: device.rssi)
                        Text("\(device.rssi) dBm")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if device.isConnectable {
                        Text("Connectable")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.thinMaterial)
                            .clipShape(Capsule())
                    }
                }
            }

            // Custom “Details” toggle instead of DisclosureGroup.
            // This avoids edge-cases where frequent updates can interfere with tap handling.
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text("Details")
                        .font(.subheadline)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                // “Details” is meant for developer inspection: show raw-ish values with
                // text selection enabled (easy copy/paste when debugging BLE payloads).
                VStack(alignment: .leading, spacing: 6) {
                    if let hex = device.manufacturerDataHex {
                        Text("Manufacturer Data: \(hex)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let tx = device.txPower {
                        Text("Tx Power: \(tx)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(device.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
    }
}

struct ContentView: View {
    @ObservedObject private var bluetoothScanner = BluetoothScanner()
    @State private var searchText = ""

    /// Set of expanded row IDs.
    ///
    /// We store this in `ContentView` (not inside the row) so expansion state survives
    /// list updates while scanning.
    @State private var expandedDeviceIds = Set<UUID>()

    var body: some View {
        VStack {
            HStack {
                // Text field for entering search text
                TextField("Search", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                // Button for clearing search text
                Button(action: {
                    self.searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(searchText == "" ? 0 : 1)
            }
            .padding()

            // List of discovered peripherals filtered by search text
            List(
                bluetoothScanner.discoveredPeripherals.filter { device in
                    guard !searchText.isEmpty else { return true }
                    let needle = searchText.lowercased()
                    // Keep search simple and predictable: match against name + manufacturer info.
                    let haystack = [
                        device.name,
                        device.manufacturerName ?? "",
                        device.manufacturerCompanyId.map { String(format: "%04x", $0) } ?? ""
                    ].joined(separator: " ").lowercased()
                    return haystack.contains(needle)
                },
                id: \.id
            ) { device in
                PeripheralRowView(
                    device: device,
                    // Bind per-row expansion state to a Set<UUID>.
                    // This makes the UI stable even when `discoveredPeripherals` updates.
                    isExpanded: Binding(
                        get: { expandedDeviceIds.contains(device.id) },
                        set: { newValue in
                            if newValue {
                                expandedDeviceIds.insert(device.id)
                            } else {
                                expandedDeviceIds.remove(device.id)
                            }
                        }
                    )
                )
            }

            // Button for starting or stopping scanning
            Button(action: {
                if self.bluetoothScanner.isScanning {
                    self.bluetoothScanner.stopScan()
                } else {
                    self.bluetoothScanner.startScan()
                }
            }) {
                if bluetoothScanner.isScanning {
                    Text("Stop Scanning")
                } else {
                    Text("Scan for Devices")
                }
            }
            // Button looks cooler this way on iOS
            .padding()
            .background(bluetoothScanner.isScanning ? Color.red : Color.blue)
            .foregroundColor(Color.white)
            .cornerRadius(5.0)
        }
    }
}
