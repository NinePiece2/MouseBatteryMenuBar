import AppKit
import Combine
import Foundation
import IOKit
import IOKit.hid
import SwiftUI

private func debugLog(_ message: String) {
    print("[LogiMouse] \(message)")
}

enum BatteryState: Equatable {
    case unknown
    case discharging(Int)
    case charging(Int)

    var percentage: Int? {
        switch self {
        case .unknown: return nil
        case let .discharging(value), let .charging(value): return value
        }
    }

    var isCharging: Bool {
        if case .charging = self { return true }
        return false
    }
}

struct MouseDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let deviceIndex: UInt8

    static func == (lhs: MouseDevice, rhs: MouseDevice) -> Bool { lhs.id == rhs.id }
}

final class IOHIDDeviceManager: @unchecked Sendable {
    private var manager: IOHIDManager?
    private var devices: [IOHIDDevice] = []
    private let responseLock = NSLock()
    private var pendingResponses: [UInt8: [UInt8]] = [:]

    var onDevicesChanged: (() -> Void)?

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = manager else { return }

        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x046D
        ]

        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let mySelf = Unmanaged<IOHIDDeviceManager>.fromOpaque(context).takeUnretainedValue()
            mySelf.deviceConnected(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let mySelf = Unmanaged<IOHIDDeviceManager>.fromOpaque(context).takeUnretainedValue()
            mySelf.deviceDisconnected(device)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        debugLog("IOHIDManager initialized with hotplug support.")
    }

    private func setupDevice(_ dev: IOHIDDevice) {
        responseLock.lock()
        if devices.contains(dev) {
            responseLock.unlock()
            return
        }
        devices.append(dev)
        responseLock.unlock()

        IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

        IOHIDDeviceRegisterInputReportCallback(
            dev,
            reportBuffer,
            64,
            { context, result, sender, type, reportID, report, reportLength in
                guard let context = context else { return }
                let mySelf = Unmanaged<IOHIDDeviceManager>.fromOpaque(context).takeUnretainedValue()
                let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
                mySelf.handleInputReport(bytes)
            },
            context
        )
        IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    private func deviceConnected(_ device: IOHIDDevice) {
        setupDevice(device)
        debugLog("Hotplug: Logitech device connected.")
        onDevicesChanged?()
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        responseLock.lock()
        devices.removeAll { $0 == device }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        responseLock.unlock()
        debugLog("Hotplug: Logitech device disconnected.")
        onDevicesChanged?()
    }

    private func handleInputReport(_ bytes: [UInt8]) {
        guard bytes.count >= 4 else { return }
        responseLock.lock()
        let key = bytes[1]
        pendingResponses[key] = bytes
        responseLock.unlock()
    }

    func getDeviceName(deviceIndex: UInt8) -> String? {
        guard let featResp = sendAndReceive(deviceIndex: deviceIndex, featureIndex: 0x00, function: 0x00, params: [0x00, 0x05]),
              featResp.count >= 5, featResp[4] != 0 else {
            return nil
        }
        let featureIndex = featResp[4]

        guard let countResp = sendAndReceive(deviceIndex: deviceIndex, featureIndex: featureIndex, function: 0x00, params: []),
              countResp.count >= 5 else {
            return nil
        }
        let nameLength = Int(countResp[4])
        guard nameLength > 0 else { return nil }

        var nameBytes: [UInt8] = []
        var charIndex: UInt8 = 0
        
        while charIndex < UInt8(nameLength) {
            guard let nameResp = sendAndReceive(deviceIndex: deviceIndex, featureIndex: featureIndex, function: 0x10, params: [charIndex]),
                  nameResp.count > 4 else { break }
            
            let chunk = Array(nameResp[4..<nameResp.count])
            if chunk.isEmpty { break }
            
            for byte in chunk {
                if byte != 0 && nameBytes.count < nameLength {
                    nameBytes.append(byte)
                }
            }
            
            charIndex += UInt8(chunk.count)
        }

        if !nameBytes.isEmpty, let name = String(bytes: nameBytes, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines)), !name.isEmpty {
            return name
        }
        return nil
    }

    func sendAndReceive(deviceIndex: UInt8, featureIndex: UInt8, function: UInt8, params: [UInt8]) -> [UInt8]? {
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = 0x11
        report[1] = deviceIndex
        report[2] = featureIndex
        report[3] = (function & 0xF0)
        for (i, p) in params.prefix(16).enumerated() {
            report[4 + i] = p
        }

        responseLock.lock()
        pendingResponses.removeValue(forKey: deviceIndex)
        let currentDevices = self.devices
        responseLock.unlock()

        for device in currentDevices {
            let setRes = IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(report[0]),
                report,
                report.count
            )

            if setRes == kIOReturnSuccess {
                let deadline = Date().addingTimeInterval(0.08)
                while Date() < deadline {
                    responseLock.lock()
                    if let resp = pendingResponses[deviceIndex] {
                        pendingResponses.removeValue(forKey: deviceIndex)
                        responseLock.unlock()
                        return resp
                    }
                    responseLock.unlock()
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }
        }

        return nil
    }
}

@MainActor
final class MouseService: ObservableObject {
    @Published var devices: [MouseDevice] = []
    @Published var selectedDeviceID: String?
    @Published var batteryState: BatteryState = .unknown
    @Published var lastError: String?
    @Published var refreshIntervalSeconds: TimeInterval = 300 {
        didSet { setupTimer() }
    }
    @Published var showPercentageInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showPercentageInMenuBar, forKey: "showPercentageInMenuBar") }
    }

    private var hid: IOHIDDeviceManager?
    private var timer: Timer?
    private var refreshWorkItem: DispatchWorkItem?

    init() {
        self.showPercentageInMenuBar = UserDefaults.standard.object(forKey: "showPercentageInMenuBar") as? Bool ?? true
        let hidManager = IOHIDDeviceManager()
        hidManager.onDevicesChanged = { [weak self] in
            Task { @MainActor in
                self?.debouncedRefreshDevices()
            }
        }
        self.hid = hidManager

        debouncedRefreshDevices()
        setupTimer()
    }

    private func debouncedRefreshDevices() {
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshDevicesWithRetry()
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func setupTimer() {
        timer?.invalidate()
        guard refreshIntervalSeconds > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: refreshIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshBattery()
            }
        }
    }

    func select(_ device: MouseDevice) {
        selectedDeviceID = device.id
        refreshBattery()
    }

    func refreshDevices() {
        refreshDevicesWithRetry(attempt: 1)
    }

    private func refreshDevicesWithRetry(attempt: Int = 1) {
        guard let hid = hid else {
            lastError = "Could not initialize IOHIDManager interface."
            return
        }

        Task.detached {
            var foundMice: [MouseDevice] = []
            let slotsToTest: [UInt8] = [0xFF, 0x01, 0x02, 0x03, 0x04]
            var primaryDeviceFound = false

            for slot in slotsToTest {
                if primaryDeviceFound && slot != 0xFF { continue }

                if let rootResp = hid.sendAndReceive(deviceIndex: slot, featureIndex: 0x00, function: 0x00, params: [0x00, 0x05]),
                   rootResp.count >= 5, rootResp[4] != 0 {
                    
                    let mouseName = hid.getDeviceName(deviceIndex: slot) ?? "Logitech Mouse"
                    debugLog("Found Logitech Mouse at Index 0x\(String(format: "%02X", slot)): \"\(mouseName)\"")
                    
                    foundMice.append(MouseDevice(id: "slot-\(slot)", name: mouseName, deviceIndex: slot))
                    if slot == 0xFF { primaryDeviceFound = true }
                }
            }

            let results = foundMice
            await MainActor.run { [results] in
                if results.isEmpty && attempt < 4 {
                    debugLog("No devices found on attempt \(attempt). Retrying in 1 second...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.refreshDevicesWithRetry(attempt: attempt + 1)
                    }
                    return
                }

                self.devices = results
                if results.isEmpty {
                    self.selectedDeviceID = nil
                    self.batteryState = .unknown
                    debugLog("No devices found. Resetting battery state to unknown.")
                } else {
                    if self.selectedDeviceID == nil || !results.contains(where: { $0.id == self.selectedDeviceID }) {
                        self.selectedDeviceID = results.first?.id
                    }
                    self.refreshBattery()
                }
            }
        }
    }

    func refreshBattery() {
        guard let device = devices.first(where: { $0.id == selectedDeviceID }),
              let hid = hid else {
            DispatchQueue.main.async {
                self.batteryState = .unknown
            }
            return
        }

        Task.detached {
            let slot = device.deviceIndex

            if let featResp = hid.sendAndReceive(deviceIndex: slot, featureIndex: 0x00, function: 0x00, params: [0x10, 0x04]),
               featResp.count >= 5, featResp[4] != 0 {
                let batFeatIdx = featResp[4]
                if let batData = hid.sendAndReceive(deviceIndex: slot, featureIndex: batFeatIdx, function: 0x10, params: []),
                   batData.count >= 7 {
                    let pct = min(Int(batData[4]), 100)
                    if pct > 0 {
                        let charging = batData[6] == 0x01 || batData[6] == 0x02
                        debugLog("Battery 0x1004 -> Pct: \(pct)%, Charging: \(charging)")
                        await MainActor.run {
                            self.batteryState = charging ? .charging(pct) : .discharging(pct)
                        }
                        return
                    }
                }
            }

            if let featResp = hid.sendAndReceive(deviceIndex: slot, featureIndex: 0x00, function: 0x00, params: [0x10, 0x00]),
               featResp.count >= 5, featResp[4] != 0 {
                let batFeatIdx = featResp[4]
                if let batData = hid.sendAndReceive(deviceIndex: slot, featureIndex: batFeatIdx, function: 0x10, params: []),
                   batData.count >= 6 {
                    let pct = min(Int(batData[5]), 100)
                    if pct > 0 {
                        let charging = (batData[4] & 0x07) == 0x01
                        debugLog("Battery 0x1000 -> Pct: \(pct)%, Charging: \(charging)")
                        await MainActor.run {
                            self.batteryState = charging ? .charging(pct) : .discharging(pct)
                        }
                        return
                    }
                }
            }

            debugLog("Skipping transient invalid/zero battery frame.")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = MouseService()
    private var batterySubscription: AnyCancellable?
    private var percentageSubscription: AnyCancellable?
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        popover = NSPopover()
        popover.contentSize = NSSize(width: 240, height: 260)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuView(service: service))

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.imagePosition = .imageLeading
        }

        updateIcon(for: service.batteryState)

        batterySubscription = service.$batteryState.sink { [weak self] state in
            self?.updateIcon(for: state)
        }

        percentageSubscription = service.$showPercentageInMenuBar.sink { [weak self] _ in
            guard let self = self else { return }
            self.updateIcon(for: self.service.batteryState)
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateIcon(for state: BatteryState) {
        guard let button = statusItem.button else { return }
        let name: String
        switch state {
        case .unknown: name = "battery.0percent"
        case let .charging(value): name = value >= 75 ? "battery.100percent.bolt" : "battery.50percent.bolt"
        case let .discharging(value): name = value >= 75 ? "battery.100percent" : value >= 25 ? "battery.50percent" : "battery.0percent"
        }
        
        button.image = createCombinedImage(batterySymbolName: name)
        button.imagePosition = .imageLeading

        if service.showPercentageInMenuBar {
            if let pct = state.percentage {
                button.title = " \(pct)%"
            } else {
                button.title = " --%"
            }
        } else {
            button.title = ""
        }
        
        button.needsDisplay = true
    }

    private func createCombinedImage(batterySymbolName: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let mouseImage = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Mouse")?.withSymbolConfiguration(config)
        let batteryImage = NSImage(systemSymbolName: batterySymbolName, accessibilityDescription: "Battery")?.withSymbolConfiguration(config)
        
        let size = NSSize(width: 48, height: 18)
        let compositeImage = NSImage(size: size)
        
        compositeImage.lockFocus()
        mouseImage?.draw(in: NSRect(x: 0, y: 2, width: 14, height: 14), from: .zero, operation: .sourceOver, fraction: 1.0)
        batteryImage?.draw(in: NSRect(x: 16, y: 2, width: 30, height: 14), from: .zero, operation: .sourceOver, fraction: 1.0)
        
        compositeImage.unlockFocus()
        compositeImage.isTemplate = true
        return compositeImage
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}