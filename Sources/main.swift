// JabraMicMute
// Menu bar app that listens for the mute button on a Jabra Evolve2 30 SE
// (or any Jabra headset) and toggles the Mac's default input device mute.
//
// Copyright (C) 2026 Saif Hassan
// SPDX-License-Identifier: AGPL-3.0-or-later

import Cocoa
import CoreAudio
import IOKit.hid
import ServiceManagement

// MARK: - Config

enum AppConfig {
    // Run the binary from a terminal with --debug to see every HID event
    // the headset sends. Useful if the mute button uses an unexpected usage.
    static let debug = CommandLine.arguments.contains("--debug")
    static let preview = CommandLine.arguments.contains("--preview") || Bundle.main.bundleIdentifier?.hasSuffix("-preview") == true
    static var inputMode = InputMonitorMode(tracingEnabled: debug)
    // Pass --no-consumer-mute if the Consumer/Mute fallback causes the
    // speaker mute to fire twice on your unit.
    static let handleConsumerMute = !CommandLine.arguments.contains("--no-consumer-mute")
}

// Verbose diagnostics, enabled by --debug or the live input window.
func debugLog(_ message: @autoclosure () -> String) {
    guard AppConfig.inputMode.tracingEnabled else { return }
    AppLog.log("[debug] \(message())")
}

// MARK: - File logging (~/Library/Logs/JabraTeamsRemap.log)
// Production logging is intentionally sparse: lifecycle, permission state,
// device connect/disconnect, and errors. Everything else goes to debugLog.

enum AppLog {
    static var onLine: ((String) -> Void)?
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/JabraTeamsRemap.log")

    private static let maxSize: UInt64 = 262_144 // 256 KB, then rotate to .old

    private static func rotateIfNeeded() {
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? UInt64,
           size > maxSize {
            let old = url.deletingPathExtension().appendingPathExtension("old.log")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func log(_ message: String) {
        rotateIfNeeded()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        if AppConfig.debug { print(line, terminator: "") }
        onLine?(line)
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

// MARK: - Microphone mute control (CoreAudio)

final class MicMuteController {
    var onChange: (() -> Void)?

    private var currentDevice = AudioDeviceID(kAudioObjectUnknown)
    private var deviceListenerInstalled = false
    private let savedVolumeKey = "JabraMicMute.savedInputVolume"

    private var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private lazy var propertyListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { self?.onChange?() }
    }

    private lazy var defaultDeviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async {
            self?.attachToDefaultDevice()
            self?.onChange?()
        }
    }

    init() {
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            .main,
            defaultDeviceListener
        )
        attachToDefaultDevice()
    }

    private func defaultInputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : AudioDeviceID(kAudioObjectUnknown)
    }

    private func attachToDefaultDevice() {
        let newDevice = defaultInputDevice()
        guard newDevice != currentDevice else { return }

        if deviceListenerInstalled, currentDevice != kAudioObjectUnknown {
            for selector in [kAudioDevicePropertyMute, kAudioDevicePropertyVolumeScalar] {
                var addr = inputAddress(selector, element: UInt32(kAudioObjectPropertyElementMain))
                AudioObjectRemovePropertyListenerBlock(currentDevice, &addr, .main, propertyListener)
            }
            deviceListenerInstalled = false
        }

        currentDevice = newDevice
        guard currentDevice != kAudioObjectUnknown else { return }

        for selector in [kAudioDevicePropertyMute, kAudioDevicePropertyVolumeScalar] {
            var addr = inputAddress(selector, element: UInt32(kAudioObjectPropertyElementMain))
            if AudioObjectHasProperty(currentDevice, &addr) {
                AudioObjectAddPropertyListenerBlock(currentDevice, &addr, .main, propertyListener)
                deviceListenerInstalled = true
            }
        }
        AppLog.log("default input device: \(deviceName())")
    }

    private func inputAddress(_ selector: AudioObjectPropertySelector, element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
    }

    // Elements that expose a given input property. Prefers the main element;
    // falls back to per-channel elements (1, 2) for devices without a master control.
    private func elements(supporting selector: AudioObjectPropertySelector) -> [UInt32] {
        guard currentDevice != kAudioObjectUnknown else { return [] }
        var addr = inputAddress(selector, element: UInt32(kAudioObjectPropertyElementMain))
        if AudioObjectHasProperty(currentDevice, &addr) {
            return [UInt32(kAudioObjectPropertyElementMain)]
        }
        var found: [UInt32] = []
        for channel: UInt32 in [1, 2] {
            addr.mElement = channel
            if AudioObjectHasProperty(currentDevice, &addr) { found.append(channel) }
        }
        return found
    }

    func deviceName() -> String {
        guard currentDevice != kAudioObjectUnknown else { return "No input device" }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameRef: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(currentDevice, &addr, 0, nil, &size, &nameRef)
        guard status == noErr, let name = nameRef?.takeRetainedValue() else { return "Unknown device" }
        return name as String
    }

    var isMuted: Bool {
        let muteElements = elements(supporting: kAudioDevicePropertyMute)
        if !muteElements.isEmpty {
            for element in muteElements {
                var addr = inputAddress(kAudioDevicePropertyMute, element: element)
                var value: UInt32 = 0
                var size = UInt32(MemoryLayout<UInt32>.size)
                if AudioObjectGetPropertyData(currentDevice, &addr, 0, nil, &size, &value) == noErr,
                   value != 0 {
                    return true
                }
            }
            return false
        }
        // No mute property; fall back to treating near-zero volume as muted.
        return (inputVolume() ?? 1.0) < 0.01
    }

    func toggle() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        guard currentDevice != kAudioObjectUnknown else { return }
        var success = false

        for element in elements(supporting: kAudioDevicePropertyMute) {
            var addr = inputAddress(kAudioDevicePropertyMute, element: element)
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(currentDevice, &addr, &settable) == noErr,
                  settable.boolValue else { continue }
            var value: UInt32 = muted ? 1 : 0
            if AudioObjectSetPropertyData(currentDevice, &addr, 0, nil,
                                          UInt32(MemoryLayout<UInt32>.size), &value) == noErr {
                success = true
            }
        }

        if !success {
            // Device has no usable mute switch; emulate one with input volume.
            if muted {
                if let volume = inputVolume(), volume > 0.01 {
                    UserDefaults.standard.set(volume, forKey: savedVolumeKey)
                }
                setInputVolume(0)
            } else {
                let saved = UserDefaults.standard.object(forKey: savedVolumeKey) as? Float
                setInputVolume(saved ?? 0.8)
            }
        }

        debugLog("microphone \(muted ? "MUTED" : "UNMUTED") via \(success ? "mute property" : "volume fallback") on \(deviceName())")
        onChange?()
    }

    private func inputVolume() -> Float? {
        for element in elements(supporting: kAudioDevicePropertyVolumeScalar) {
            var addr = inputAddress(kAudioDevicePropertyVolumeScalar, element: element)
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(currentDevice, &addr, 0, nil, &size, &volume) == noErr {
                return volume
            }
        }
        return nil
    }

    private func setInputVolume(_ volume: Float) {
        for element in elements(supporting: kAudioDevicePropertyVolumeScalar) {
            var addr = inputAddress(kAudioDevicePropertyVolumeScalar, element: element)
            var value = Float32(volume)
            AudioObjectSetPropertyData(currentDevice, &addr, 0, nil,
                                       UInt32(MemoryLayout<Float32>.size), &value)
        }
    }
}

// MARK: - Jabra HID button listener (IOKit)

final class JabraButtonListener {
    var onMuteTapped: (() -> Void)?
    var onPlayTapped: (() -> Void)?
    var onMappedButton: ((HeadsetButton) -> Void)?
    var onLearnedSignal: ((ButtonSignal) -> Void)?
    private var mappedButtons: [HeadsetButton] = []
    private var buttonAvailability = ButtonAvailability.load()
    private var headsetModels = HeadsetModelAssignments.load()
    var isLearning = false
    var legacyControls = false
    private var buttonRouter = HeadsetButtonRouter()
    private var readyAfter: [ObjectIdentifier: TimeInterval] = [:]
    private let compatibility = TeamsCompatibilityController()
    var standaloneStatus: String { compatibility.status }
    private(set) var inputReportCount = 0
    private(set) var lastInputAt: Date?

    func updateSettings(_ settings: ButtonSettings, buttons: [HeadsetButton]? = nil) {
        buttonAvailability = ButtonAvailability.load()
        headsetModels = HeadsetModelAssignments.load()
        compatibility.setEnabled(settings.standaloneTeamsButton == true)
        mappedButtons = buttons ?? [HeadsetButton(id: "teams", name: "Teams", settings: settings)]
        buttonRouter.reset()
        let wasLegacy = legacyControls
        if wasLegacy && !settings.legacyControls { releaseOffHook() }
        legacyControls = settings.legacyControls
        if legacyControls { assertOffHook() }
    }

    static let jabraVendorID = 0x0B0E // GN Audio / Jabra

    private static let telephonyPage: UInt32 = 0x0B
    private static let phoneMuteUsage: UInt32 = 0x2F
    private static let hookSwitchUsage: UInt32 = 0x20
    private static let consumerPage: UInt32 = 0x0C
    private static let consumerMuteUsage: UInt32 = 0xE2
    private static let playPauseUsage: UInt32 = 0xCD
    private static let playUsage: UInt32 = 0xB0
    private static let pauseUsage: UInt32 = 0xB1
    private static let ledPage: UInt32 = 0x08
    private static let ledMuteUsage: UInt32 = 0x09
    private static let ledOffHookUsage: UInt32 = 0x17

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var devices: [IOHIDDevice] = []
    private var lastTrigger = Date.distantPast
    private var lastPlayTrigger = Date.distantPast
    private var lastPhoneMuteValue: CFIndex = 0
    private var lastHookValue: CFIndex = 0
    private var offHookTimer: Timer?
    // Hook transitions we caused ourselves (sleep/wake, intentional release)
    // must not be mistaken for middle-button presses.
    private var suppressHookUntil = Date.distantPast
    private(set) var isRunning = false

    var connectedDeviceCount: Int { devices.count }
    private(set) var inputSelection = HeadsetInputSelection.load()
    private func identity(_ device: IOHIDDevice) -> ConnectedHeadset {
        ConnectedHeadset(
            productID: (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0,
            locationID: (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? NSNumber)?.intValue ?? 0,
            name: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Jabra headset",
            serialNumber: IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String)
    }
    var detectedDevices: [ConnectedHeadset] {
        var seen = Set<String>()
        return devices.map(identity).filter { seen.insert($0.id).inserted }.sorted { $0.name < $1.name }
    }
    func selectDevice(_ id: String?) {
        guard id == nil || detectedDevices.contains(where: { $0.id == id }) else { return }
        if legacyControls { releaseOffHook() }
        inputSelection.deviceID = id; inputSelection.save()
        buttonRouter.reset()
        if legacyControls { assertOffHook() }
        AppLog.log("HEADSET selected: \(detectedDevices.first { $0.id == id }?.name ?? "All connected headsets")")
        NotificationCenter.default.post(name: .jabraDevicesChanged, object: nil)
    }

    func logDeviceSummary() {
        for device in devices {
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Jabra"
            let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
            AppLog.log("DEVICE \(product), product=0x\(String(productID, radix: 16))")
            guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement] else { continue }
            for element in elements {
                let type = IOHIDElementGetType(element)
                guard type == kIOHIDElementTypeInput_Button || type == kIOHIDElementTypeInput_Misc || type == kIOHIDElementTypeInput_Axis else { continue }
                debugLog("ELEMENT page=0x\(String(IOHIDElementGetUsagePage(element), radix: 16)) usage=0x\(String(IOHIDElementGetUsage(element), radix: 16)) report=\(IOHIDElementGetReportID(element)) cookie=\(IOHIDElementGetCookie(element)) bits=\(IOHIDElementGetReportSize(element))")
            }
        }
    }

    func start() -> Bool {
        let matching: [String: Any] = [kIOHIDVendorIDKey: Self.jabraVendorID]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let me = Unmanaged<JabraButtonListener>.fromOpaque(context).takeUnretainedValue()
            me.deviceAdded(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let me = Unmanaged<JabraButtonListener>.fromOpaque(context).takeUnretainedValue()
            me.deviceRemoved(device)
        }, context)

        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let me = Unmanaged<JabraButtonListener>.fromOpaque(context).takeUnretainedValue()
            me.handle(value)
        }, context)

        IOHIDManagerRegisterInputReportCallback(manager, { context, result, sender, type, reportID, bytes, length in
            guard let context else { return }
            let listener = Unmanaged<JabraButtonListener>.fromOpaque(context).takeUnretainedValue()
            listener.inputReportCount += 1
            listener.lastInputAt = Date()
            guard AppConfig.inputMode.tracingEnabled, let sender, length >= 0 else { return }
            let reference = Unmanaged<CFTypeRef>.fromOpaque(sender).takeUnretainedValue()
            guard CFGetTypeID(reference) == IOHIDDeviceGetTypeID() else { return }
            let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            let product = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
            let location = (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? NSNumber)?.stringValue ?? "?"
            let report = UnsafeBufferPointer(start: bytes, count: length)
            let hex = report.prefix(256).map { String(format: "%02X", $0) }.joined(separator: " ")
            debugLog("RAW product=0x\(String(product, radix: 16)) location=\(location) type=\(type.rawValue) report=\(reportID) length=\(length) result=\(result) bytes=[\(hex)]\(length > 256 ? " (first 256 bytes)" : "")")
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isRunning = result == kIOReturnSuccess
        AppLog.log("HID manager open: \(isRunning ? "OK" : "FAILED (0x\(String(UInt32(bitPattern: result), radix: 16)))")")
        return isRunning
    }

    // Called on a timer after a failed open, e.g. once the user has granted
    // Input Monitoring in System Settings.
    func retryOpen() -> Bool {
        guard !isRunning else { return true }
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isRunning = result == kIOReturnSuccess
        if isRunning { AppLog.log("HID manager opened after retry") }
        return isRunning
    }

    // The manager can open while Input Monitoring is denied, but no button
    // events arrive. Once permission is granted, cycle the connection so
    // event delivery starts without relaunching the app.
    func reopenAfterPermissionChange() {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isRunning = result == kIOReturnSuccess
        AppLog.log("HID manager reopened after permission change: \(isRunning ? "OK" : "FAILED")")
    }

    private func deviceAdded(_ device: IOHIDDevice) {
        if !devices.contains(where: { $0 === device }) {
            devices.append(device)
            readyAfter[ObjectIdentifier(device)] = ProcessInfo.processInfo.systemUptime + 4
        }
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        AppLog.log("Jabra HID interface connected: \(product ?? "unknown") (\(devices.count) total)")
        compatibility.deviceAdded(device)

        // Log the writable elements once, so we know which LEDs this unit has.
        if AppConfig.inputMode.tracingEnabled, let all = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement] {
            let outputs = all
                .filter { IOHIDElementGetType($0) == kIOHIDElementTypeOutput }
                .map { "0x\(String(IOHIDElementGetUsagePage($0), radix: 16)):0x\(String(IOHIDElementGetUsage($0), radix: 16))" }
            debugLog("writable elements: \(outputs.joined(separator: " "))")
        }

        // Call mode is opt-in for the original mute/Music controls.
        assertOffHook()
        if offHookTimer == nil {
            // Self-heal only: no USB traffic while the headset is off-hook.
            offHookTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                guard let self, self.legacyControls, !self.isLearning, self.lastHookValue == 0, !self.devices.isEmpty else { return }
                self.assertOffHook()
            }
        }
        NotificationCenter.default.post(name: .jabraDevicesChanged, object: nil)
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        readyAfter.removeValue(forKey: ObjectIdentifier(device))
        compatibility.deviceRemoved(device)
        devices.removeAll { $0 === device }
        buttonRouter.reset()
        AppLog.log("Jabra HID interface disconnected (\(devices.count) left)")
        NotificationCenter.default.post(name: .jabraDevicesChanged, object: nil)
    }

    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        // Vendor-defined arrays can be larger than CFIndex. They need report
        // decoding, not IOHIDValueGetIntegerValue (which can trap on long data).
        guard IOHIDValueGetLength(value) <= MemoryLayout<CFIndex>.size else {
            debugLog("non-scalar HID input page=0x\(String(page, radix: 16)) usage=0x\(String(usage, radix: 16)); needs report decoding")
            return
        }
        let intValue = IOHIDValueGetIntegerValue(value)
        let device = IOHIDElementGetDevice(element)
        let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
        let location = (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? NSNumber)?.stringValue ?? "unknown"
        let signal = ButtonSignal(productID: productID, usagePage: page, usage: usage,
                                  reportID: IOHIDElementGetReportID(element),
                                  cookie: IOHIDElementGetCookie(element), value: intValue,
                                  deviceName: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String)
        debugLog("VALUE \(signal.label) location=\(location)")
        guard inputSelection.accepts(identity(device)) else { return }
        let activeModel = headsetModels.model(for: identity(device))
        let availableButtons = mappedButtons.filter { buttonAvailability.isAvailable($0.id, model: activeModel) }
        let matches = buttonRouter.consume(signal, device: location, buttons: availableButtons, now: ProcessInfo.processInfo.systemUptime)
        if isLearning { onLearnedSignal?(signal); return }
        for button in matches {
            if signal.usagePage == 0xFF99,
               ProcessInfo.processInfo.systemUptime < (readyAfter[ObjectIdentifier(device)] ?? 0) {
                AppLog.log("BUTTON ignored: headset is initializing after USB connection")
                continue
            }
            AppLog.log("BUTTON matched [\(button.name)]: \(signal.label)")
            if AppConfig.inputMode.dispatchesActions(isLearning: isLearning) { onMappedButton?(button) }
            else { AppLog.log("ACTION skipped: mapped actions paused") }
        }
        // Learned mappings add actions. Opt-in legacy controls can still handle the same event.
        guard AppConfig.inputMode.dispatchesActions(isLearning: isLearning), legacyControls else { return }

        debugLog("HID event page=0x\(String(page, radix: 16)) usage=0x\(String(usage, radix: 16)) value=\(intValue)")

        let now = Date()

        // With off-hook asserted, the mute button acts host-managed: it pulses
        // 0x2f 1-then-0 per press and expects the host to decide the state
        // (and reflect it back via the mute LED). Toggle on the press edge only.
        if page == Self.telephonyPage && usage == Self.phoneMuteUsage {
            if intValue != lastPhoneMuteValue {
                lastPhoneMuteValue = intValue
                if intValue != 0, now.timeIntervalSince(lastTrigger) > 0.25 {
                    lastTrigger = now
                    debugLog("mute button pressed")
                    DispatchQueue.main.async { self.onMuteTapped?() }
                }
            }
            return
        }

        // Hook switch: 0 -> 1 is just the headset acknowledging our off-hook
        // assertion. 1 -> 0 means the headset dropped the "call", which only
        // happens when the user presses the middle button. Re-assert off-hook
        // shortly after so the mute button keeps transmitting.
        if page == Self.telephonyPage && usage == Self.hookSwitchUsage {
            if intValue != lastHookValue {
                let wasOffHook = lastHookValue != 0
                lastHookValue = intValue
                if wasOffHook && intValue == 0 && now >= suppressHookUntil {
                    if now.timeIntervalSince(lastPlayTrigger) > 0.25 {
                        lastPlayTrigger = now
                        debugLog("middle button pressed (hook switch)")
                        DispatchQueue.main.async { self.onPlayTapped?() }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.assertOffHook()
                    }
                }
            }
            return
        }

        // Momentary buttons below: react on press only, ignore release.
        guard intValue != 0 else { return }

        if AppConfig.handleConsumerMute && page == Self.consumerPage && usage == Self.consumerMuteUsage {
            guard now.timeIntervalSince(lastTrigger) > 0.25 else { return }
            lastTrigger = now
            debugLog("mute button pressed (consumer mute)")
            DispatchQueue.main.async { self.onMuteTapped?() }
            return
        }

        if page == Self.consumerPage,
           usage == Self.playPauseUsage || usage == Self.playUsage || usage == Self.pauseUsage {
            guard now.timeIntervalSince(lastPlayTrigger) > 0.25 else { return }
            lastPlayTrigger = now
            debugLog("middle button pressed (play/pause)")
            DispatchQueue.main.async { self.onPlayTapped?() }
        }
    }

    // Best effort: mirror the mic state onto the headset's mute LED, if the
    // device exposes one as a standard HID LED element.
    func setMuteLED(on: Bool) {
        guard legacyControls, !isLearning else { return }
        setLED(usage: Self.ledMuteUsage, on: on)
    }

    // Tell the headset a call is active. Jabra headsets only transmit the
    // mute button over USB while off-hook; idle presses are local-only.
    //
    // The handshake matters: after the device drops the call (hook input 0),
    // re-writing off-hook=1 is ignored as stale state. The host must first
    // acknowledge with off-hook=0, then raise it again to start a new "call".
    func assertOffHook() {
        guard legacyControls, !isLearning else { return }
        if lastHookValue != 0 {
            // Device already off-hook; refresh the state.
            setLED(usage: Self.ledOffHookUsage, on: true)
        } else {
            debugLog("re-establishing call mode (off-hook pulse)")
            setLED(usage: Self.ledOffHookUsage, on: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.legacyControls, !self.isLearning else { return }
                self.setLED(usage: Self.ledOffHookUsage, on: true)
            }
        }
    }

    // Return the headset to idle when the app quits, so it isn't left
    // believing a call is active with nobody listening.
    func releaseOffHook() {
        guard legacyControls else { return }
        suppressHookUntil = Date().addingTimeInterval(5)
        setLED(usage: Self.ledMuteUsage, on: false)
        setLED(usage: Self.ledOffHookUsage, on: false)
    }

    // System sleep: hang up gracefully so the headset idles overnight.
    func prepareForSleep() {
        compatibility.sleep()
        debugLog("system sleeping; releasing off-hook")
        suppressHookUntil = Date().addingTimeInterval(30)
        releaseOffHook()
    }

    // Wake: re-arm call mode after the USB stack settles.
    func wake() {
        compatibility.wake()
        debugLog("system woke; re-arming call mode")
        suppressHookUntil = Date().addingTimeInterval(5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.assertOffHook()
        }
    }

    private func setLED(usage: UInt32, on: Bool) {
        let matching: [String: Any] = [
            kIOHIDElementUsagePageKey: Int(Self.ledPage),
            kIOHIDElementUsageKey: Int(usage),
        ]
        for device in devices where inputSelection.accepts(identity(device)) {
            guard let elements = IOHIDDeviceCopyMatchingElements(device, matching as CFDictionary, 0) as? [IOHIDElement],
                  !elements.isEmpty else { continue }
            for element in elements {
                let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, mach_absolute_time(), on ? 1 : 0)
                let result = IOHIDDeviceSetValue(device, element, value)
                if result != kIOReturnSuccess {
                    AppLog.log("LED write failed (usage 0x\(String(usage, radix: 16)), 0x\(String(UInt32(bitPattern: result), radix: 16)))")
                }
            }
        }
    }

    func stopCompatibility() { compatibility.stop() }
}

extension Notification.Name {
    static let jabraDevicesChanged = Notification.Name("JabraMicMute.devicesChanged")
}

// MARK: - Desktop overlay HUD (like the system volume bezel)

final class MuteHUD {
    private let panel: NSPanel
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var hideTimer: Timer?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 68),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 17
        effect.layer?.masksToBounds = true

        label.font = .systemFont(ofSize: 16, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyUpOrDown

        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34),
        ])
        panel.contentView = effect
    }

    func show(muted: Bool) {
        let symbol = muted ? "mic.slash.fill" : "mic.fill"
        let color: NSColor = muted ? .systemRed : .systemGreen
        let config = NSImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        label.stringValue = muted ? "Microphone Muted" : "Microphone On"

        position()
        hideTimer?.invalidate()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                self.panel.animator().alphaValue = 0
            }, completionHandler: {
                self.panel.orderOut(nil)
            })
        }
    }

    private func position() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + frame.height * 0.12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - App delegate / menu bar UI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private let profilePopover = NSPopover()
    private var popoverPreviewWindow: NSWindow?
    private var profilePopoverController: ProfilePopover?
    private let mic = MicMuteController()
    private let audioActivity = AudioActivityMonitor()
    private let voiceMonitor = CodexVoiceMonitor()
    private let grokVoiceMonitor = CodexVoiceMonitor(processID: {
        NSRunningApplication.runningApplications(withBundleIdentifier: GrokVoiceSession.bundleID).first?.processIdentifier
    }, readState: { GrokVoiceSession.probe(processID: $0) })
    private let jabra = JabraButtonListener()
    private let hud = MuteHUD()
    private let agentHUD = AgentSwitchHUD()
    private var profileLibrary: ButtonProfileLibrary = {
        do {
            if var saved = try ButtonProfileLibrary.load() {
                if let grok = AgentApplications.url(for: "Grok"), saved.migrateGrokWebProfile(to: grok.path) { try saved.save() }
                if saved.agentCatalogVersion == nil {
                    try saved.configureAgentCatalog(["Codex", "Grok Bot", "Claude", "Hermes", "OpenClaw"].map { (name: $0, target: AgentApplications.url(for: $0)?.path) })
                    try saved.save()
                }
                if saved.migrateAutomaticActions() { try saved.save() }
                if let codex = saved.profiles.first(where: { Bundle(path: $0.settings.target)?.bundleIdentifier == "com.openai.codex" }), saved.installCodexActionPresets(for: codex.id) { try saved.save() }
                return saved
            }
        }
        catch { AppLog.log("Profile library unreadable; recovering current setup: \(error.localizedDescription)") }
        var settings = ButtonSettings.load()
        if UserDefaults.standard.data(forKey: ButtonSettings.defaultsKey) == nil,
           let url = AgentApplications.url(for: "Codex") {
            settings.action = .openApp; settings.target = url.path
        }
        let currentName: String
        if settings.action == .openURL && URL(string: settings.target)?.host?.contains("grok.com") == true { currentName = "Grok" }
        else if settings.action == .openApp && Bundle(path: settings.target)?.bundleIdentifier == "com.openai.codex" { currentName = "Codex" }
        else if settings.target.hasSuffix("/Siri.app") { currentName = "Siri" }
        else { currentName = "My setup" }
        var presets: [(name: String, action: ButtonAction, target: String)] = []
        if let url = AgentApplications.url(for: "Codex") { presets.append(("Codex", .openApp, url.path)) }
        presets.append(("Grok", .openApp, AgentApplications.url(for: "Grok")?.path ?? "/Applications/Grok Bot.app"))
        if let url = AgentApplications.url(for: "Siri") { presets.append(("Siri", .openApp, url.path)) }
        var library = ButtonProfileLibrary.seeded(current: settings, currentName: currentName, alternatives: presets)
        try? library.configureAgentCatalog(["Codex", "Grok Bot", "Claude", "Hermes", "OpenClaw"].map { (name: $0, target: AgentApplications.url(for: $0)?.path) })
        if let codex = library.profiles.first(where: { Bundle(path: $0.settings.target)?.bundleIdentifier == "com.openai.codex" }) { _ = library.installCodexActionPresets(for: codex.id) }
        do { try library.save() } catch { AppLog.log("Could not save migrated profiles: \(error.localizedDescription)") }
        return library
    }()
    private var buttonSettings: ButtonSettings { profileLibrary.active.settings }
    private let profilesMenu = NSMenu()
    private let runProfilesMenu = NSMenu()
    private let hotkeys = GlobalHotkeys()
    private var shortcutFailures: [String] = []
    private var profileMenuItem: NSMenuItem!
    private var configurationWindow: ConfigurationWindow?
    private var launcherWindow: ProfileLauncherWindow?
    private var settingsWindow: ButtonSettingsWindow?
    private var secondaryWindow: AgentActionsWindow?
    private var secondaryInFlight: Set<String> = []
    private var profileRunsInFlight: Set<UUID> = []
    private var agentsWindow: AgentsWindow?
    private var buttonsWindow: ButtonsWindow?
    private var debugWindow: InputDebugWindow?
    private let actionGeneration = ActionGeneration()
    private var pendingActions: [String: Timer] = [:]
    private func cancelPendingActions() { actionGeneration.cancel(); pendingActions.values.forEach { $0.invalidate() }; pendingActions.removeAll() }
    private var lastMuted: Bool?
    private var ledSyncedMuted: Bool?
    private var retryTimer: Timer?
    private var permissionPollTimer: Timer?

    private var inputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    private var deviceInfoItem: NSMenuItem!
    private var jabraStatusItem: NSMenuItem!
    private var muteItem: NSMenuItem!
    private var permissionItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    func applicationWillTerminate(_ notification: Notification) {
        cancelPendingActions()
        hotkeys.clear()
        audioActivity.stop()
        voiceMonitor.stop()
        grokVoiceMonitor.stop()
        jabra.stopCompatibility()
        jabra.releaseOffHook()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppLog.log("--- app launched; input logging and mapped actions are independent ---")
        buildStatusItem()
        audioActivity.selectionProvider = { [weak self] in
            guard let self else { return (false, nil) }
            let id = self.jabra.inputSelection.deviceID
            return (id != nil, self.jabra.detectedDevices.first { $0.id == id })
        }
        audioActivity.start()
        hotkeys.onTrigger = { [weak self] binding in
            guard let self else { return }
            switch binding.purpose {
            case .activate: self.selectProfile(binding.profileID)
            case .run: self.runProfile(binding.profileID)
            case .previous: self.cycleAgent(-1)
            case .next: self.cycleAgent(1)
            case .secondary: if let actionID = binding.secondaryActionID { self.runNamedAction(binding.profileID, actionID) }
            }
        }
        ButtonActionExecutor.agentActionHandler = { [weak self] reference, completion in
            guard let self else { completion("Headset Remap is not running."); return }
            self.runNamedAction(reference.profileID, reference.actionID, completion: completion)
        }
        configureHotkeys()
        jabra.updateSettings(buttonSettings, buttons: profileLibrary.active.resolvedButtons)
        jabra.onMappedButton = { [weak self] button in self?.scheduleButtonAction(button) }
        jabra.onLearnedSignal = { [weak self] signal in
            self?.settingsWindow?.receive(signal); self?.buttonsWindow?.receive(signal)
        }

        mic.onChange = { [weak self] in self?.refreshUI() }
        jabra.onMuteTapped = { [weak self] in self?.mic.toggle() }
        jabra.onPlayTapped = { [weak self] in self?.handleMiddleButton() }
        NotificationCenter.default.addObserver(
            forName: .jabraDevicesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.cancelPendingActions()
            self?.audioActivity.refreshSelection()
            self?.ledSyncedMuted = nil // re-sync LED on (re)connect
            self?.refreshUI()
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancelPendingActions()
            self?.jabra.prepareForSleep()
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.ledSyncedMuted = nil
            self?.jabra.wake()
            self?.refreshUI()
        }

        if CommandLine.arguments.contains("--preview-popover") {
            refreshUI(); openPopoverPreview(); return
        }
        if AppConfig.preview {
            refreshUI()
            if CommandLine.arguments.contains("--configuration") { openConfiguration() }
            else if CommandLine.arguments.contains("--agents") { openAgents() }
            else if CommandLine.arguments.contains("--buttons") { openButtons() }
            else if CommandLine.arguments.contains("--launcher") { openLauncher() }
            else if CommandLine.arguments.contains("--settings") { openButtonSettings() } else { openConfiguration() }
            return
        }
        startListening()
        voiceMonitor.onChange = { [weak self] state in
            AppLog.log("VOICE Codex state: \(state.rawValue)")
            self?.refreshUI()
        }
        grokVoiceMonitor.onChange = { [weak self] state in
            AppLog.log("VOICE Grok Bot state: \(state.rawValue)")
            self?.refreshUI()
        }
        voiceMonitor.start()
        grokVoiceMonitor.start()
        refreshUI()
        if CommandLine.arguments.contains("--agents") { openAgents() }
        if CommandLine.arguments.contains("--buttons") { openButtons() }
        if CommandLine.arguments.contains("--launcher") { openLauncher() }
        if CommandLine.arguments.contains("--settings") { openButtonSettings() }
        if AppConfig.debug { openDebugInput() }
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        deviceInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        deviceInfoItem.isEnabled = false
        deviceInfoItem.isHidden = true
        menu.addItem(deviceInfoItem)

        jabraStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        jabraStatusItem.isEnabled = false
        menu.addItem(jabraStatusItem)

        menu.addItem(.separator())

        profileMenuItem = NSMenuItem(title: "Headset uses", action: nil, keyEquivalent: "")
        profileMenuItem.submenu = profilesMenu
        menu.addItem(profileMenuItem)
        let runItem = NSMenuItem(title: "Open agent now", action: nil, keyEquivalent: "")
        runItem.submenu = runProfilesMenu; menu.addItem(runItem)
        rebuildProfileMenu()

        let launcher = NSMenuItem(title: "Open launcher…", action: #selector(openLauncher), keyEquivalent: "")
        launcher.target = self; menu.addItem(launcher)
        let settingsItem = NSMenuItem(title: "Configuration…", action: #selector(openConfiguration), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let debugItem = NSMenuItem(title: "Debug Input…", action: #selector(openDebugInput), keyEquivalent: "d")
        debugItem.target = self
        menu.addItem(debugItem)

        muteItem = NSMenuItem(title: "Mute Microphone", action: #selector(toggleMute), keyEquivalent: "m")
        muteItem.target = self
        menu.addItem(muteItem)

        menu.addItem(.separator())

        permissionItem = NSMenuItem(title: "Grant Input Monitoring…", action: #selector(openInputMonitoringSettings), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        let logMenuItem = NSMenuItem(title: "Open Log File", action: #selector(openLog), keyEquivalent: "")
        logMenuItem.target = self
        let diagnostics = NSMenuItem(title: "Troubleshooting", action: nil, keyEquivalent: "")
        let diagnosticsMenu = NSMenu()
        menu.removeItem(debugItem)
        diagnosticsMenu.addItem(debugItem); diagnosticsMenu.addItem(logMenuItem)
        diagnostics.submenu = diagnosticsMenu; menu.addItem(diagnostics)

        loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let about = NSMenuItem(title: "About Headset Remap", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit Headset Remap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusMenu = menu
        if let button = statusItem.button {
            button.target = self; button.action = #selector(toggleProfilePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        profilePopover.behavior = .transient
        let controller = ProfilePopover(library: profileLibrary, connection: headsetStatus, devices: jabra.detectedDevices, selectedDeviceID: jabra.inputSelection.deviceID)
        controller.onSelectDevice = { [weak self] id in self?.jabra.selectDevice(id) }
        controller.onSelect = { [weak self] id in self?.selectProfile(id) }
        controller.onSecondaryRun = { [weak self] profileID, actionID in self?.profilePopover.performClose(nil); self?.runNamedAction(profileID, actionID) }
        controller.onActions = { [weak self] id in self?.profilePopover.performClose(nil); self?.openSecondaryActions(id) }
        controller.onRun = { [weak self] id in self?.profilePopover.performClose(nil); self?.runProfile(id) }
        controller.onSettings = { [weak self] in self?.profilePopover.performClose(nil); self?.openLauncher() }
        controller.onConfiguration = { [weak self] in self?.profilePopover.performClose(nil); self?.openConfiguration() }
        profilePopoverController = controller; profilePopover.contentViewController = controller
    }

    // Inspect the exact popover content in a standard window when native popovers are not exposed by UI automation.
    private func openPopoverPreview() {
        if popoverPreviewWindow == nil, let controller = profilePopoverController {
            profilePopover.contentViewController = nil
            _ = controller.view
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: controller.preferredContentSize),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Menu bar preview"; window.isReleasedWhenClosed = false
            window.contentViewController = controller; window.center()
            popoverPreviewWindow = window
        }
        popoverPreviewWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    private var headsetStatus: String {
        if AppConfig.preview { return "Preview · headset input inactive" }
        if !inputMonitoringGranted { return "Input permission needed" }
        let devices = jabra.detectedDevices
        if let id = jabra.inputSelection.deviceID {
            return devices.first { $0.id == id }.map { "Using \($0.name)" } ?? "Selected headset disconnected"
        }
        if devices.count == 1 { return "Connected: \(devices[0].name)" }
        return devices.isEmpty ? "Headset not connected" : "\(devices.count) headsets connected"
    }
    @objc private func toggleProfilePopover() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            profilePopover.performClose(nil)
            statusItem.menu = statusMenu; button.performClick(nil); statusItem.menu = nil
        } else if profilePopover.isShown { profilePopover.performClose(nil) }
        else {
            profilePopoverController?.update(library: profileLibrary, connection: headsetStatus, devices: jabra.detectedDevices, selectedDeviceID: jabra.inputSelection.deviceID)
            profilePopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    private func startListening() {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let accessText = access == kIOHIDAccessTypeGranted ? "granted"
            : access == kIOHIDAccessTypeDenied ? "DENIED" : "not determined"
        AppLog.log("input monitoring access: \(accessText)")
        if access != kIOHIDAccessTypeGranted {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        if !jabra.start() {
            scheduleOpenRetry()
        }
        // Opening can succeed while Input Monitoring is denied, but button
        // events silently never arrive. Treat missing permission as the
        // problem it is: tell the user and watch for the grant.
        if !inputMonitoringGranted {
            showPermissionAlert()
            schedulePermissionPoll()
        }
    }

    private func schedulePermissionPoll() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, self.inputMonitoringGranted else { return }
            self.permissionPollTimer?.invalidate()
            self.permissionPollTimer = nil
            AppLog.log("input monitoring granted; reconnecting to headset")
            self.jabra.reopenAfterPermissionChange()
            self.refreshUI()
        }
    }

    private func scheduleOpenRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.jabra.retryOpen() {
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                self.refreshUI()
            }
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Input Monitoring permission needed"
        alert.informativeText = """
        Headset Remap needs Input Monitoring access to see the headset's buttons.

        In System Settings → Privacy & Security → Input Monitoring, turn ON \
        "Headset Remap". The app reconnects by itself once you grant it.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openInputMonitoringSettings()
        }
    }

    // Red rounded badge with a white slashed mic; unmistakable in the menu bar.
    private func mutedStatusIcon() -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.systemRed.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: "mic.slash.fill", accessibilityDescription: "Microphone muted")?
                .withSymbolConfiguration(config) {
                let s = symbol.size
                symbol.draw(
                    at: NSPoint(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2),
                    from: .zero, operation: .sourceOver, fraction: 1
                )
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private func refreshStatusIcon() {
        guard let button = statusItem.button else { return }
        let muted = mic.isMuted
        let states = [("Codex", voiceMonitor.state), ("Grok Bot", grokVoiceMonitor.state)]
        let active = states.filter { $0.1 == .active }.map { $0.0 }
        let status = states.map { $0.1.status(for: $0.0) }.joined(separator: " · ")
        if !active.isEmpty {
            button.image = CodexVoiceStatusIcon.activeImage(agent: active.joined(separator: " / "))
        } else if !buttonSettings.legacyControls {
            let image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Headset Remap")
            image?.isTemplate = true; button.image = image
        } else if muted {
            button.image = mutedStatusIcon()
        } else {
            let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Microphone on")
            image?.isTemplate = true; button.image = image
        }
        button.toolTip = "Profile: \(profileLibrary.active.name) · \(status) · \(muted ? "Microphone muted" : "Microphone on")"
        button.setAccessibilityLabel("Headset Remap · " + status)
    }

    private func refreshUI() {
        let muted = mic.isMuted
        rebuildProfileMenu()
        profilePopoverController?.update(library: profileLibrary, connection: headsetStatus, devices: jabra.detectedDevices, selectedDeviceID: jabra.inputSelection.deviceID)
        launcherWindow?.update(library: profileLibrary, connection: headsetStatus, devices: jabra.detectedDevices, selectedDeviceID: jabra.inputSelection.deviceID, activeVoiceProfileIDs: activeVoiceProfileIDs)

        refreshStatusIcon()

        deviceInfoItem.title = "Input: \(mic.deviceName())"
        if !inputMonitoringGranted {
            jabraStatusItem.title = "Jabra buttons: NO PERMISSION (Input Monitoring)"
        } else {
            jabraStatusItem.title = jabra.connectedDeviceCount > 0
                ? "Jabra headset: connected"
                : "Jabra headset: not detected"
        }
        muteItem.isHidden = !buttonSettings.legacyControls
        muteItem.state = muted ? .on : .off
        permissionItem.isHidden = inputMonitoringGranted && jabra.isRunning
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        // Overlay bezel on actual state changes (not on startup or unrelated refreshes).
        if let last = lastMuted, last != muted {
            hud.show(muted: muted)
        }
        lastMuted = muted

        // Write the headset LED only when the state actually changed.
        if ledSyncedMuted != muted {
            ledSyncedMuted = muted
            jabra.setMuteLED(on: muted)
        }
    }

    private func rebuildProfileMenu() {
        profileMenuItem?.title = "Profile: \(profileLibrary.active.name)"
        profilesMenu.removeAllItems()
        runProfilesMenu.removeAllItems()
        for profile in profileLibrary.enabledProfiles {
            let item = NSMenuItem(title: profileLibrary.displayName(profile) + (profile.activateShortcut.map { "  \($0.label)" } ?? ""), action: #selector(activateProfile(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = profile.id.uuidString
            item.state = profile.id == profileLibrary.activeID ? .on : .off
            profilesMenu.addItem(item)
            let run = NSMenuItem(title: profileLibrary.displayName(profile) + (profile.runShortcut.map { "  \($0.label)" } ?? ""), action: #selector(runProfileMenu(_:)), keyEquivalent: "")
            run.target = self; run.representedObject = profile.id.uuidString; runProfilesMenu.addItem(run)
        }
    }

    @objc private func showAbout() {
        let credits = NSMutableAttributedString(string: "Original project: Saif Hassan (saiftheboss7)\nBård Ove Myhr\nAI-assisted development: OpenAI Codex\nLicense: GNU AGPL v3\n\n")
        credits.append(NSAttributedString(string: "Read the README on GitHub", attributes: [.link: URL(string: "https://github.com/baardove/headset-remap/blob/main/README.md")!]))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Headset Remap", .credits: credits])
    }

    @objc private func activateProfile(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else { return }
        selectProfile(id)
    }
    private func cycleAgent(_ offset: Int) {
        guard let target = profileLibrary.cycleTarget(offset: offset) else { return }
        selectProfile(target.id)
        guard profileLibrary.activeID == target.id else { return }
        agentHUD.show(target, number: profileLibrary.number(for: target.id), beside: statusItem.button)
    }
    private func selectProfile(_ id: UUID) {
        if let settingsWindow { settingsWindow.selectProfile(id); return }
        var next = profileLibrary
        do { try next.select(id); try next.save(); applyProfiles(next) }
        catch { AppLog.log("Could not activate profile: \(error.localizedDescription)") }
    }

    private func applyProfiles(_ library: ButtonProfileLibrary) {
        cancelPendingActions()
        profileLibrary = library
        jabra.updateSettings(buttonSettings, buttons: profileLibrary.active.resolvedButtons)
        secondaryWindow?.update(library)
        agentsWindow?.update(library)
        settingsWindow?.synchronize(library)
        buttonsWindow?.update(library)
        configureHotkeys()
        ledSyncedMuted = nil
        AppLog.log("PROFILE active: \(library.active.name)")
        refreshUI()
    }

    private func configureHotkeys() {
        if AppConfig.preview {
            hotkeys.clear(); shortcutFailures = []
        } else { shortcutFailures = hotkeys.configure(profileLibrary) }
        for failure in shortcutFailures { AppLog.log("KEYBOARD: \(failure)") }
        settingsWindow?.refreshShortcutStatus()
    }

    @objc private func runProfileMenu(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else { return }
        runProfile(id)
    }
    private func runProfile(_ id: UUID) {
        guard let profile = profileLibrary.enabledProfiles.first(where: { $0.id == id }) else { return }
        guard !profileRunsInFlight.contains(id) else {
            AppLog.log("RUN ignored repeated trigger: \(profile.name) is already running its actions")
            return
        }
        let isCurrent = actionGeneration.checkpoint()
        if stopGrokVoiceIfActive(profile, isCurrent: isCurrent) { return }
        if CodexVoiceToggle.stopIfActive(profile: profile) { voiceMonitor.refresh(); return }
        // Direct runs preserve headset selection and omit its focus delay, but use
        // the same configured primary/secondary sequence from every Run surface.
        profileRunsInFlight.insert(id)
        AppLog.log("RUN sequence started: \(profile.name)")
        AutomaticAgentActions.run(afterPrimary: { complete in
            ButtonActionExecutor.run(profile.settings, completion: complete)
        }, actions: profile.automaticActions, isCurrent: isCurrent, perform: { [weak self] action, next in
            guard let self else { next("Action sequence canceled."); return }
            self.executeSecondary(action, profile: profile, isCurrent: isCurrent, completion: next)
        }, completion: { [weak self] error in
            self?.profileRunsInFlight.remove(id)
            AppLog.log(error.map { "RUN sequence failed: \($0)" } ?? "RUN sequence completed: \(profile.name)")
        })
    }

    private func stopGrokVoiceIfActive(_ profile: ButtonProfile, isCurrent: @escaping () -> Bool) -> Bool {
        GrokVoiceSession.stopIfActive(profile: profile, isCurrent: isCurrent) { [weak self] error in
            AppLog.log(error.map { "VOICE Grok Bot stop failed: \($0)" } ?? "VOICE Grok Bot stopped: active session")
            self?.grokVoiceMonitor.refresh()
        }
    }

    private var activeVoiceProfileIDs: Set<UUID> {
        Set(profileLibrary.enabledProfiles.filter { profile in
            (grokVoiceMonitor.state == .active && GrokVoiceSession.supportsToggle(profile)) ||
            (voiceMonitor.state == .active && CodexVoiceToggle.isConfigured(in: profile))
        }.map(\.id))
    }

    /// Explicit Stop must never fall back to starting a new session if the UI is stale.
    private func stopProfileVoice(_ id: UUID) {
        guard let profile = profileLibrary.enabledProfiles.first(where: { $0.id == id }) else { return }
        if stopGrokVoiceIfActive(profile, isCurrent: actionGeneration.checkpoint()) { return }
        if CodexVoiceToggle.stopIfActive(profile: profile) { voiceMonitor.refresh(); return }
        grokVoiceMonitor.refresh(); voiceMonitor.refresh()
        AppLog.log("VOICE stop ignored: no confirmed active voice for \(profile.name)")
    }

    private func runNamedAction(_ profileID: UUID, _ actionID: UUID, completion: @escaping (String?) -> Void = { _ in }) {
        guard let profile = profileLibrary.enabledProfiles.first(where: { $0.id == profileID }),
              let action = profile.secondaryActions?.first(where: { $0.id == actionID }) else { completion("This agent action is unavailable or disabled."); return }
        executeSecondary(action, profile: profile, completion: completion)
    }
    private func executeSecondary(_ action: AgentSecondaryAction, profile: ButtonProfile, isCurrent: @escaping () -> Bool = { true }, completion: @escaping (String?) -> Void) {
        let key = AgentActionReference(profileID: profile.id, actionID: action.id).encoded
        guard !secondaryInFlight.contains(key) else { completion("That action is already running."); return }
        if action.kind == .keyboard, let stroke = action.key, profileLibrary.hotkeys.contains(where: { $0.shortcut == stroke }) {
            completion("Choose an app shortcut different from Headset Remap’s global shortcuts."); return
        }
        secondaryInFlight.insert(key)
        AppLog.log("AGENT ACTION started: \(profile.name) · \(action.name)")
        let currentGeneration = actionGeneration.checkpoint()
        AgentActionExecutor.run(action, profile: profile, isCurrent: { currentGeneration() && isCurrent() }) { [weak self] error in
            self?.secondaryInFlight.remove(key)
            AppLog.log(error.map { "AGENT ACTION failed: \($0)" } ?? "AGENT ACTION completed: \(action.name)")
            completion(error)
        }
    }
    private func openSecondaryActions(_ profileID: UUID) {
        guard prepareNavigation() else { return }
        if secondaryWindow?.profileID != profileID { secondaryWindow?.close(); secondaryWindow = nil }
        if secondaryWindow == nil {
            let controller = AgentActionsWindow(library: profileLibrary, profileID: profileID)
            controller.onBack = { [weak self] in self?.openAgents() }
            controller.onChange = { [weak self] library in self?.applyProfiles(library) }
            controller.onRecording = { [weak self] recording in if recording { self?.hotkeys.clear() } else { self?.configureHotkeys() } }
            controller.onTest = { [weak self] profileID, action, completion in
                guard let self, let profile = self.profileLibrary.profiles.first(where: { $0.id == profileID }) else { completion("Agent not found."); return }
                self.executeSecondary(action, profile: profile, completion: completion)
            }
            secondaryWindow = controller
        }
        showOnly(secondaryWindow)
        secondaryWindow?.present()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if CommandLine.arguments.contains("--preview-popover") {
            openPopoverPreview()
        } else { openLauncher() }
        return true
    }
    @objc private func openLauncher() {
        guard prepareNavigation() else { return }
        if launcherWindow == nil {
            let controller = ProfileLauncherWindow(library: profileLibrary, connection: headsetStatus, devices: jabra.detectedDevices, selectedDeviceID: jabra.inputSelection.deviceID, activeVoiceProfileIDs: activeVoiceProfileIDs)
            controller.onSelectDevice = { [weak self] id in self?.jabra.selectDevice(id) }
        controller.onSelect = { [weak self] id in self?.selectProfile(id) }
            controller.onRun = { [weak self] id in self?.runProfile(id) }
            controller.onStopVoice = { [weak self] id in self?.stopProfileVoice(id) }
            controller.onSettings = { [weak self] in self?.openConfiguration() }
            launcherWindow = controller
        }
        showOnly(launcherWindow)
        launcherWindow?.present()
    }
    /// Resolve drafts before switching screens, and stop learning when leaving its screen.
    private func prepareNavigation() -> Bool {
        guard agentsWindow?.prepareForExternalEdit() != false,
              settingsWindow?.prepareForExternalEdit() != false,
              buttonsWindow?.prepareForExternalEdit() != false,
              secondaryWindow?.prepareForExternalEdit() != false else { return false }
        settingsWindow?.cancelLearning(); buttonsWindow?.cancelLearning()
        return true
    }
    private func showOnly(_ destination: NSWindowController?) {
        let screens: [NSWindowController?] = [configurationWindow, launcherWindow, agentsWindow, secondaryWindow, buttonsWindow, settingsWindow]
        for screen in screens.compactMap({ $0 }) where screen !== destination { screen.window?.orderOut(nil) }
        if AppConfig.preview, let window = destination?.window, !window.title.hasPrefix("Preview · ") {
            window.title = "Preview · " + window.title
        }
    }
    @objc private func openConfiguration() {
        guard prepareNavigation() else { return }
        if configurationWindow == nil {
            let controller = ConfigurationWindow()
            controller.onLauncher = { [weak self] in self?.openLauncher() }
            controller.onAgents = { [weak self] in self?.openAgents() }
            controller.onButtons = { [weak self] in self?.openButtons() }
            controller.onAdvanced = { [weak self] in self?.openKeyboardShortcuts() }
            controller.onDebug = { [weak self] in self?.openDebugInput() }
            configurationWindow = controller
        }
        showOnly(configurationWindow)
        configurationWindow?.present(agent: profileLibrary.active.name)
    }
    @objc private func openKeyboardShortcuts() {
        guard prepareNavigation() else { return }
        openButtonSettings(); settingsWindow?.presentShortcuts()
    }
    @objc private func openAgents() {
        guard prepareNavigation() else { return }
        if agentsWindow == nil {
            let controller = AgentsWindow(library: profileLibrary)
            controller.onBack = { [weak self] in self?.openConfiguration() }
            controller.onActions = { [weak self] id in self?.openSecondaryActions(id) }
            controller.onCycle = { [weak self] offset in self?.cycleAgent(offset) }
            controller.onShortcutRecording = { [weak self] recording in
                if recording { self?.hotkeys.clear() } else { self?.configureHotkeys() }
            }
            controller.onChange = { [weak self] library in self?.applyProfiles(library) }
            agentsWindow = controller
        }
        showOnly(agentsWindow)
        agentsWindow?.present()
    }
    @objc private func openButtons() {
        guard prepareNavigation() else { return }
        if buttonsWindow == nil {
            let controller = ButtonsWindow(library: profileLibrary)
            controller.devicesProvider = { [weak self] in self?.jabra.detectedDevices ?? [] }
            controller.onBack = { [weak self] in self?.openConfiguration() }
            controller.onChange = { [weak self] library in self?.applyProfiles(library) }
            controller.onAvailabilityChanged = { [weak self] in
                guard let self else { return }
                self.cancelPendingActions()
                self.jabra.updateSettings(self.buttonSettings, buttons: self.profileLibrary.active.resolvedButtons)
            }
            controller.audioStatusProvider = { [weak self] in self?.audioActivity.status ?? "" }
            controller.onDebug = { [weak self] in self?.openDebugInput() }
            controller.onLearningChanged = { [weak self] learning in
                if learning { self?.cancelPendingActions(); self?.settingsWindow?.cancelLearning() }
                self?.jabra.isLearning = learning
            }
            buttonsWindow = controller
        }
        showOnly(buttonsWindow)
        buttonsWindow?.present()
    }
    @objc private func openButtonSettings() {
        guard prepareNavigation() else { return }
        if settingsWindow == nil {
            let controller = ButtonSettingsWindow(library: profileLibrary)
            controller.onBack = { [weak self] in self?.openConfiguration() }
            controller.shortcutStatusProvider = { [weak self] in self?.shortcutFailures.joined(separator: "\n") ?? "" }
            controller.onShortcutRecording = { [weak self] recording in
                if recording { self?.hotkeys.clear() } else { self?.configureHotkeys() }
            }
            controller.onAgentsRequested = { [weak self] in self?.openAgents() }
            controller.onButtonsRequested = { [weak self] in self?.openButtons() }
            controller.onDebugRequested = { [weak self] in self?.openDebugInput() }
            controller.onChange = { [weak self] library in self?.applyProfiles(library) }
            controller.statusProvider = { [weak self] in
                guard let self else { return "" }
                if !self.inputMonitoringGranted { return "Allow Input Monitoring to use your headset button." }
                if self.jabra.connectedDeviceCount == 0 { return "Connect your Jabra headset to use the button." }
                return "Headset connected · Ready"
            }
            controller.onLearningChanged = { [weak self] learning in
                if learning { self?.cancelPendingActions(); self?.buttonsWindow?.cancelLearning() }
                self?.jabra.isLearning = learning
            }
            settingsWindow = controller
        }
        showOnly(settingsWindow)
        settingsWindow?.present()
    }

    private func scheduleButtonAction(_ button: HeadsetButton) {
        guard button.settings.action != .none else { return }
        let condition = button.settings.activationCondition ?? .always
        // Use the sampled pre-press state. The physical play/pause event may itself change playback.
        guard condition.permits(audioActivity.state) else {
            AppLog.log("ACTION skipped [\(button.name)]: \(condition.title); \(audioActivity.status)")
            return
        }
        pendingActions.removeValue(forKey: button.id)?.invalidate()
        let settings = button.settings
        let profileID = profileLibrary.activeID
        let headsetSelection = jabra.inputSelection
        let currentGeneration = actionGeneration.checkpoint()
        let run = { [weak self] in
            guard let self, currentGeneration(), self.profileLibrary.activeID == profileID,
                  self.jabra.inputSelection == headsetSelection,
                  self.profileLibrary.active.resolvedButtons.first(where: { $0.id == button.id })?.settings == settings,
                  AppConfig.inputMode.dispatchesActions(isLearning: self.jabra.isLearning) else { return }
            self.pendingActions.removeValue(forKey: button.id)
            if let profile = self.profileLibrary.profiles.first(where: { $0.id == profileID }),
               settings.action == profile.settings.action, settings.target == profile.settings.target {
                if self.stopGrokVoiceIfActive(profile, isCurrent: currentGeneration) { return }
                if CodexVoiceToggle.stopIfActive(profile: profile) { return }
            }
            AppLog.log("ACTION started: \(settings.action.title) [profile: \(self.profileLibrary.active.name), button: \(button.name)]")
            ButtonActionExecutor.run(settings) { error in
                if let error { AppLog.log("ACTION failed: \(error)") }
                else {
                    AppLog.log("ACTION completed: target accepted the request")
                    guard currentGeneration(), let profile = self.profileLibrary.profiles.first(where: { $0.id == profileID }),
                          settings.action == profile.settings.action, settings.target == profile.settings.target else { return }
                    AutomaticAgentActions.run(profile.automaticActions, perform: { action, next in
                        guard self.profileLibrary.activeID == profileID, self.jabra.inputSelection == headsetSelection, AppConfig.inputMode.dispatchesActions(isLearning: self.jabra.isLearning) else { next("Agent or headset changed; remaining actions canceled."); return }
                        self.executeSecondary(action, profile: profile, isCurrent: { currentGeneration() && AppConfig.inputMode.dispatchesActions(isLearning: self.jabra.isLearning) }, completion: next)
                    }, completion: { error in
                        if let error { AppLog.log("AUTOMATIC ACTIONS stopped: \(error)") }
                        else { AppLog.log("AUTOMATIC ACTIONS completed") }
                    })
                }
            }
        }
        let delay = settings.effectiveFocusTiming.delay
        if delay == 0 { run(); return }
        AppLog.log("ACTION scheduled [\(button.name)]: waiting \(Int(delay * 1000)) ms")
        pendingActions[button.id] = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in run() }
    }

    @objc private func openDebugInput() {
        if debugWindow == nil {
            debugWindow = InputDebugWindow()
            debugWindow?.onActionsPaused = { [weak self] in self?.cancelPendingActions() }
            debugWindow?.statusProvider = { [weak self] in
                guard let self else { return "" }
                let age = self.jabra.lastInputAt.map { "\(Int(Date().timeIntervalSince($0)))s ago" } ?? "none yet"
                return "Audio: \(self.audioActivity.status)\nPermission: \(self.inputMonitoringGranted ? "granted" : "missing") · Jabra interfaces: \(self.jabra.connectedDeviceCount) · Reports: \(self.jabra.inputReportCount) · Last input: \(age)\n\(self.jabra.standaloneStatus)"
            }
        }
        debugWindow?.present()
        AppLog.log("Input capture: permission=\(inputMonitoringGranted ? "granted" : "missing"), Jabra interfaces=\(jabra.connectedDeviceCount)")
        jabra.logDeviceSummary()
    }

    @objc private func toggleMute() {
        mic.toggle()
    }

    // Middle button: launch Apple Music if it isn't running, otherwise
    // toggle play/pause in it.
    private func handleMiddleButton() {
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
            openAppleMusic()
        } else {
            playPauseMusic()
        }
    }

    private func openAppleMusic() {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music")
            ?? URL(fileURLWithPath: "/System/Applications/Music.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        debugLog("opening Apple Music")
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                AppLog.log("failed to open Apple Music: \(error.localizedDescription)")
            }
        }
    }

    private func playPauseMusic() {
        debugLog("toggling Music play/pause")
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Music\" to playpause")?
            .executeAndReturnError(&error)
        if let error {
            AppLog.log("Music playpause failed: \(error[NSAppleScript.errorMessage] ?? error)")
        }
    }

    @objc private func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(AppLog.url)
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not update login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refreshUI()
    }
}

// MARK: - Entry point

// Read-only diagnostic through the real app bundle's Accessibility identity.
if let index = CommandLine.arguments.firstIndex(of: "--probe-ui-button"), CommandLine.arguments.count > index + 2 {
    let bundleID = CommandLine.arguments[index + 1]
    let label = CommandLine.arguments[index + 2]
    guard let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
        print("Target app is not running."); exit(1)
    }
    let result = AgentUIButton.find(label: label, processID: target.processIdentifier)
    if let error = result.error { print(error); exit(1) }
    var actions: CFArray?
    let supported = result.control.map { AXUIElementCopyActionNames($0, &actions) == .success && (actions as? [String])?.contains(kAXPressAction) == true } ?? false
    print("Found one enabled button ‘\(label)’ in \(bundleID); AXPress supported=\(supported). No button pressed.")
    exit(supported ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
