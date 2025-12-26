# Bluetooth Scanner App (iOS + macOS)

This app scans for nearby Bluetooth Low Energy (BLE) devices and shows them in a readable, developer-friendly list UI. It’s a small SwiftUI + CoreBluetooth example project.

## Features

Changelog: See [CHANGELOG.md](CHANGELOG.md).

- Scan for nearby BLE devices
- Search/filter by device name and manufacturer information
- Signal strength UI: RSSI bars + dBm value
- “Last seen” timestamp shown in relative format (e.g. “2s ago”)
- Connectable badge (when reported by CoreBluetooth)
- Expandable per-device “Details” section with:
	- Manufacturer data (hex)
	- Tx Power (if present)
	- A readable advertisement-data dump

## UI stability while scanning

BLE discovery callbacks can arrive very frequently. To keep the list stable and reliably tappable (especially for expanding “Details”), the scanner throttles UI updates per device and only publishes updates when:

- A minimum time interval has passed, or
- A relevant value changed significantly (RSSI delta threshold, connectable state, manufacturer/txPower/name changes)

## Requirements

- iOS 15.6 or later
- macOS 12.4 or later
- Xcode 14 or later

## Installation

Clone or download the repository, open `BLEScanner.xcodeproj` in Xcode, then build and run on iOS (device/simulator) or macOS.

## Bluetooth permissions

iOS requires Bluetooth usage descriptions in the app’s Info.plist (permission prompt). In this project, they are provided via Xcode build settings (`INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription` and `INFOPLIST_KEY_NSBluetoothPeripheralUsageDescription`).

macOS builds typically require the App Sandbox + Bluetooth capability (configured via entitlements).

## Released in the Apple App Store

Download:
https://apps.apple.com/de/app/simple-ble-scanner/id1663446245?l=en

## Credits

Developed by Christian Moeller, Jan 2023

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

This app is available under the MIT License. See `LICENSE.md` for more info.

