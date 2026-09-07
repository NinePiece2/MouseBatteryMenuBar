import SwiftUI

struct MenuView: View {
    @ObservedObject var service: MouseService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LogiMouse Battery")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
            
            Divider()

            if service.devices.isEmpty {
                HStack {
                    Spacer()
                    Text("No devices found")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Device")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)

                    Picker("Mouse", selection: Binding(
                        get: { service.selectedDeviceID ?? "" },
                        set: { id in
                            if let device = service.devices.first(where: { $0.id == id }) {
                                service.select(device)
                            }
                        }
                    )) {
                        ForEach(service.devices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                HStack {
                    Image(systemName: iconName)
                        .font(.system(size: 20))
                        .foregroundColor(iconColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusText)
                            .font(.system(size: 13, weight: .medium))
                        if let pct = service.batteryState.percentage {
                            ProgressView(value: Double(pct), total: 100)
                                .accentColor(iconColor)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            // Menu Bar Options
            Toggle("Show Percentage in Bar", isOn: $service.showPercentageInMenuBar)
                .font(.system(size: 11))
                .toggleStyle(.checkbox)

            // Refresh Interval Settings Picker
            HStack {
                Text("Refresh Interval:")
                    .font(.system(size: 11))
                Spacer()
                Picker("Interval", selection: $service.refreshIntervalSeconds) {
                    Text("1 min").tag(TimeInterval(60))
                    Text("5 mins").tag(TimeInterval(300))
                    Text("15 mins").tag(TimeInterval(900))
                    Text("30 mins").tag(TimeInterval(1800))
                }
                .pickerStyle(.menu)
                .frame(width: 90)
                .font(.system(size: 11))
            }

            Divider()

            HStack {
                Button("Refresh Now") {
                    service.refreshDevices()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                
                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
                .font(.system(size: 11))
            }
        }
        .padding(12)
        .frame(width: 240)
    }

    private var statusText: String {
        guard let percentage = service.batteryState.percentage else {
            return "Battery unavailable"
        }
        return service.batteryState.isCharging
            ? "Charging (\(percentage)%)"
            : "Discharging (\(percentage)%)"
    }

    private var iconName: String {
        switch service.batteryState {
        case .unknown: return "battery.0percent"
        case .charging: return "battery.100percent.bolt"
        case let .discharging(val):
            if val >= 75 { return "battery.100percent" }
            if val >= 25 { return "battery.50percent" }
            return "battery.25percent"
        }
    }

    private var iconColor: Color {
        if case let .discharging(val) = service.batteryState, val <= 20 {
            return .orange
        }
        return .primary
    }
}