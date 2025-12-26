# Changelog

## Unreleased (2025-12-26)

### Highlights
- Improved BLE device list readability: RSSI bars + dBm value, manufacturer info, and confirms if a device is connectable.
- Added a per-device expandable **Details** section with a readable advertisement-data dump, manufacturer hex data, and Tx Power (when present).
- Improved interaction reliability while scanning by reducing UI churn from very frequent BLE discovery callbacks.

### UI
- Device rows show:
  - Device name (when available)
  - Manufacturer information (when present)
  - Relative "last seen" time
  - RSSI visualization (bars) + numeric RSSI
  - A connectable badge (when reported by CoreBluetooth)
- Details can be expanded/collapsed per device without the list constantly jumping.

### BLE / Data Parsing
- Discovery data is now normalized into a structured per-device model (keyed by the peripheral UUID).
- Manufacturer data parsing improvements:
  - Extracts the Bluetooth SIG company identifier (little-endian) when available
  - Formats manufacturer bytes as hex for display
- Tx Power parsing: shown when present in advertisement data.
- Connectable parsing includes a compatibility fallback for older/private advertisement keys.

### Performance & Stability
- Throttles UI publishes per device while scanning to keep tapping/expansion responsive.
- Avoids constant re-sorting/re-ordering during scanning to reduce row movement.

### Platform / Build / Permissions
- Supports iOS and macOS from a single Xcode project.
- Bluetooth permission prompts are configured via Xcode build settings:
  - `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription`
  - `INFOPLIST_KEY_NSBluetoothPeripheralUsageDescription`
- macOS App Sandbox entitlements are scoped to macOS builds to avoid iOS signing issues.

### Documentation
- README updated to describe the new UI, the expandable details section, and the rationale for throttling UI updates.
- Added English developer-focused comments in the BLE scanner and SwiftUI views explaining key design decisions.
