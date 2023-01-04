//
//  ContentView.swift
//  BLEScanner
//
//  Created by Christian Möller on 02.01.23.
//

import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @ObservedObject private var bluetoothScanner = BluetoothScanner()
    @State private var searchText = ""

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
            List(bluetoothScanner.discoveredPeripherals.filter {
                self.searchText.isEmpty ? true : $0.peripheral.name?.lowercased().contains(self.searchText.lowercased()) == true
            }, id: \.peripheral.identifier) { discoveredPeripheral in
                VStack(alignment: .leading) {
                    Text(discoveredPeripheral.peripheral.name ?? "Unknown Device")
                    Text(discoveredPeripheral.advertisedData)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
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
