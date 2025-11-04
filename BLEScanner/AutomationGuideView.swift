//
//  AutomationGuideView.swift
//  BLEScanner
//
//  In-app guide for setting up Shortcuts automation
//

import SwiftUI

struct AutomationGuideView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Background Automation")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)

                        Text("Run shortcuts automatically when your ESP32 connects, even in the background!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)

                    // How it works
                    GuideSection(
                        icon: "lightbulb.fill",
                        iconColor: .yellow,
                        title: "How It Works"
                    ) {
                        Text("The app sends a notification when your ESP32 connects. iOS Shortcuts can detect this notification and automatically run any actions you configure.")
                    }

                    // Step 1
                    GuideSection(
                        icon: "1.circle.fill",
                        iconColor: .blue,
                        title: "Enable Notifications"
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. Tap the gear icon ⚙️")
                            Text("2. Enable 'Send Notifications'")
                            Text("3. Grant permissions when prompted")
                        }
                    }

                    // Step 2
                    GuideSection(
                        icon: "2.circle.fill",
                        iconColor: .blue,
                        title: "Create a Shortcut"
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. Open the Shortcuts app")
                            Text("2. Tap + to create a new shortcut")
                            Text("3. Add actions (lights, notifications, etc.)")
                            Text("4. Name it and tap Done")
                        }
                    }

                    // Step 3
                    GuideSection(
                        icon: "3.circle.fill",
                        iconColor: .blue,
                        title: "Create Automation (Choose Best Option)"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("⚠️ iOS doesn't support notification-based automation")
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)

                            Divider()

                            Text("Option A: When App Opens")
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("1. Automation → + → App")
                                Text("2. Select 'BLE Scanner'")
                                Text("3. Choose 'Is Opened'")
                                Text("4. Add: Check ESP32 Connection")
                                Text("5. If true → Run your shortcut")
                                Text("6. Turn OFF 'Ask Before Running'")
                            }
                            .font(.subheadline)

                            Text("Best for: Checking status when you open the app")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Divider()

                            Text("Option B: When Bluetooth Turns On")
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("1. Automation → + → Bluetooth")
                                Text("2. Select 'Is Connected' or 'Is Turned On'")
                                Text("3. Add: Check ESP32 Connection")
                                Text("4. If true → Run your shortcut")
                                Text("5. Turn OFF 'Ask Before Running'")
                            }
                            .font(.subheadline)

                            Text("Best for: Automatic when Bluetooth connects")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Divider()

                            Text("Option C: Location-Based (If Available)")
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("1. Automation → + → Arrive")
                                Text("2. Set your location (home/work)")
                                Text("3. Add: Check ESP32 Connection")
                                Text("4. If true → Run your shortcut")
                            }
                            .font(.subheadline)

                            Text("Best for: Arriving at specific location")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Alternative method
                    GuideSection(
                        icon: "lightbulb.fill",
                        iconColor: .yellow,
                        title: "Manual Trigger Alternative"
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("If you don't want time-based polling:")
                            Text("• Enable notifications in settings")
                            Text("• When you get 'ESP32 Connected' notification")
                            Text("• Tap it to open the app")
                            Text("• Shortcut runs automatically in foreground")
                                .padding(.top, 4)
                            Text("This requires tapping the notification, but no polling.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Important
                    GuideSection(
                        icon: "exclamationmark.triangle.fill",
                        iconColor: .orange,
                        title: "Important"
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("✅ Works when app is backgrounded")
                            Text("✅ Works when screen is locked")
                            Text("❌ Doesn't work if app is force-quit")
                            Text("\nDon't swipe up to close the app! Just press the home button to background it.")
                                .italic()
                        }
                    }

                    // Example use cases
                    GuideSection(
                        icon: "star.fill",
                        iconColor: .green,
                        title: "Example Use Cases"
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            ExampleRow(icon: "lightbulb.fill", text: "Turn on smart lights when you arrive home")
                            ExampleRow(icon: "lock.open.fill", text: "Unlock door when ESP32 connects")
                            ExampleRow(icon: "message.fill", text: "Send message to family")
                            ExampleRow(icon: "music.note", text: "Start playing music")
                            ExampleRow(icon: "thermometer", text: "Adjust thermostat")
                        }
                    }

                    // Troubleshooting
                    GuideSection(
                        icon: "wrench.and.screwdriver.fill",
                        iconColor: .red,
                        title: "Troubleshooting"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            TroubleshootRow(
                                problem: "No notification appears",
                                solution: "Check Settings → Notifications → BLE Scanner is enabled"
                            )

                            TroubleshootRow(
                                problem: "Shortcut doesn't run",
                                solution: "Make sure 'Ask Before Running' is OFF in your automation"
                            )

                            TroubleshootRow(
                                problem: "ESP32 doesn't connect",
                                solution: "Enable Auto-Connect and don't force-quit the app"
                            )
                        }
                    }

                    // Footer
                    Text("Tip: Test by backgrounding the app, turning ESP32 off, then on again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Automation Guide")
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
}

// MARK: - Guide Section
struct GuideSection<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.title3)

                Text(title)
                    .font(.headline)
            }

            content
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Example Row
struct ExampleRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 20)

            Text(text)
        }
    }
}

// MARK: - Troubleshoot Row
struct TroubleshootRow: View {
    let problem: String
    let solution: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)

                Text(problem)
                    .fontWeight(.semibold)
            }

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)

                Text(solution)
            }
            .padding(.leading, 20)
        }
    }
}

#Preview {
    AutomationGuideView()
}
