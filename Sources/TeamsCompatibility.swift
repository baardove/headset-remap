import Cocoa
import IOKit.hid

/// Maintains the idle-client handshake that makes the Teams button report over
/// USB. It is deliberately inactive when the actual Teams client is running.
final class TeamsCompatibilityController {
    private var devices: [ObjectIdentifier: IOHIDDevice] = [:]
    private var ready: Set<ObjectIdentifier> = []
    private var pending: Set<ObjectIdentifier> = []
    private var timer: Timer?
    private var generation = 0
    private var suspended = false
    private var failure: String?
    private(set) var enabled = false

    var status: String {
        guard enabled else { return "Standalone mode: off" }
        if teamsIsRunning { return "Standalone mode: paused for Microsoft Teams" }
        if let failure { return "Standalone mode: \(failure)" }
        if devices.isEmpty { return "Standalone mode: waiting for USB device" }
        return ready.isEmpty ? "Standalone mode: connecting" : "Standalone mode: active"
    }

    private var teamsIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.teams2").isEmpty ||
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.teams").isEmpty
    }

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        reset()
        AppLog.log(value ? "COMPAT enabled: local idle-client handshake" : "COMPAT disabled: keep-alive stopped")
        guard value else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func deviceAdded(_ device: IOHIDDevice) {
        let matching: [String: Any] = [kIOHIDElementUsagePageKey: 0xFF99, kIOHIDElementUsageKey: 3]
        guard let elements = IOHIDDeviceCopyMatchingElements(device, matching as CFDictionary, 0) as? [IOHIDElement],
              elements.contains(where: { IOHIDElementGetType($0) == kIOHIDElementTypeFeature && IOHIDElementGetReportID($0) == TeamsProtocol.reportID }) else { return }
        devices[ObjectIdentifier(device)] = device
        if enabled { refresh() }
    }

    func deviceRemoved(_ device: IOHIDDevice) {
        let key = ObjectIdentifier(device)
        devices.removeValue(forKey: key); ready.remove(key); pending.remove(key)
    }

    func sleep() { reset() }
    func wake() {
        guard enabled else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }
    func stop() { enabled = false; reset() }

    private func reset() {
        timer?.invalidate(); timer = nil
        generation += 1
        ready.removeAll(); pending.removeAll(); failure = nil; suspended = false
    }

    private func refresh() {
        guard enabled else { return }
        if teamsIsRunning {
            if !suspended {
                generation += 1; ready.removeAll(); pending.removeAll()
                AppLog.log("COMPAT paused: real Microsoft Teams is running")
            }
            suspended = true
            return
        }
        if suspended { AppLog.log("COMPAT resumed: Microsoft Teams is closed") }
        suspended = false
        for (key, device) in devices where !pending.contains(key) {
            pending.insert(key)
            let token = generation
            if ready.contains(key) { send(.idle, payload: [0], to: device, generation: token) { [weak self] success in
                guard let self, self.generation == token else { return }
                self.pending.remove(key)
                if !success { self.ready.remove(key) }
            }} else { handshake(device, step: 0, generation: generation) }
        }
    }

    private func handshake(_ device: IOHIDDevice, step: Int, generation token: Int) {
        let key = ObjectIdentifier(device)
        guard valid(device, token: token) else { pending.remove(key); return }
        let steps: [(TeamsProtocol.Message, [UInt8])] = [(.version, []), (.capabilities, []),
            (.locale, TeamsProtocol.localePayload(at: Date())), (.idle, [0])]
        guard step < steps.count else {
            ready.insert(key); pending.remove(key); failure = nil
            AppLog.log("COMPAT active: headset acknowledged idle-client handshake")
            return
        }
        let (message, data) = steps[step]
        send(message, payload: data, to: device, generation: token) { [weak self] success in
            guard let self, self.generation == token else { return }
            if success { self.handshake(device, step: step + 1, generation: token) }
            else { self.pending.remove(key) }
        }
    }

    private func valid(_ device: IOHIDDevice, token: Int) -> Bool {
        enabled && token == generation && devices[ObjectIdentifier(device)] != nil && !teamsIsRunning
    }

    private func send(_ message: TeamsProtocol.Message, payload: [UInt8], to device: IOHIDDevice,
                      generation token: Int, completion: @escaping (Bool) -> Void) {
        guard valid(device, token: token), let report = TeamsProtocol.report(message, payload: payload) else { completion(false); return }
        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(TeamsProtocol.reportID), report, report.count)
        guard result == kIOReturnSuccess else {
            failure = "USB write failed"
            AppLog.log("COMPAT USB write failed: \(result)")
            completion(false); return
        }
        readReply(message, from: device, token: token, attempt: 0, completion: completion)
    }

    private func readReply(_ message: TeamsProtocol.Message, from device: IOHIDDevice, token: Int,
                           attempt: Int, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.valid(device, token: token) else { completion(false); return }
            var reply = [UInt8](repeating: 0, count: TeamsProtocol.reportLength)
            var length = reply.count
            let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(TeamsProtocol.reportID), &reply, &length)
            if result == kIOReturnSuccess, (0...reply.count).contains(length),
               TeamsProtocol.accepts(Array(reply.prefix(length)), for: message) {
                debugLog("COMPAT acknowledged message 0x\(String(message.rawValue, radix: 16))")
                completion(true)
            } else if attempt < 2 {
                self.readReply(message, from: device, token: token, attempt: attempt + 1, completion: completion)
            } else {
                self.failure = "handshake not acknowledged"
                AppLog.log("COMPAT handshake failed at message 0x\(String(message.rawValue, radix: 16)); will retry")
                completion(false)
            }
        }
    }
}
