import Foundation
import CoreAudio

/// Reads routing/activity metadata only; never records the microphone or system audio.
final class AudioActivityMonitor {
    private var timer: Timer?
    private var gate = AudioActivityGate()
    private(set) var detail = "Checking headset audio…"
    var state: HeadsetAudioState { gate.state }
    var selectionProvider: (() -> (required: Bool, device: ConnectedHeadset?))?
    func refreshSelection() { gate = AudioActivityGate(); sample() }
    var onChange: (() -> Void)?
    var status: String {
        switch state {
        case .active: return "Headset audio active"
        case .idle: return "Headset audio idle"
        case .unknown: return detail
        }
    }
    func start() {
        sample()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.sample() }
    }
    func stop() { timer?.invalidate(); timer = nil }
    private func sample() {
        let old = state
        let selection = selectionProvider?() ?? (false, nil)
        let probe = Self.probe(selectionRequired: selection.0, selected: selection.1)
        detail = probe.1
        gate.update(probe.0, now: ProcessInfo.processInfo.systemUptime)
        if old != state { onChange?() }
    }
    static func probe(selectionRequired: Bool = false, selected: ConnectedHeadset? = nil) -> (HeadsetAudioState, String) {
        guard #available(macOS 14.2, *) else { return (.unknown, "Audio rules require macOS 14.2 or newer") }
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard let devices = ids(system, selector: kAudioHardwarePropertyDevices),
              let processes = ids(system, selector: kAudioHardwarePropertyProcessObjectList) else {
            return (.unknown, "Audio activity unavailable")
        }
        if selectionRequired && selected == nil { return (.unknown, "Selected headset disconnected") }
        var unmatchedIdentity = false
        let headsetIDs = Set(devices.filter { device in
            guard let streams = ids(device, selector: kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput), !streams.isEmpty else { return false }
            guard name(device).localizedCaseInsensitiveContains("jabra") else { return false }
            guard let selected else { return true }
            let match = HeadsetAudioRoute.matches(modelUID: string(device, selector: kAudioDevicePropertyModelUID), deviceUID: string(device, selector: kAudioDevicePropertyDeviceUID), selected: selected)
            if match == nil { unmatchedIdentity = true }
            return match == true
        })
        if unmatchedIdentity && headsetIDs.isEmpty { return (.unknown, "Selected headset audio identity unavailable") }
        guard !headsetIDs.isEmpty else { return (.unknown, "No Jabra audio output connected") }
        var uncertain = false
        for process in processes {
            guard number(process, selector: kAudioProcessPropertyIsRunningOutput) == 1 else { continue }
            guard let outputs = ids(process, selector: kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput) else { uncertain = true; continue }
            if !headsetIDs.isDisjoint(with: outputs) { return (.active, "A playback stream is using the headset") }
        }
        return uncertain ? (.unknown, "Audio routing changed; checking again…") : (.idle, "No playback stream is using the headset")
    }
    private static func ids(_ object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID]? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return nil }
        if size == 0 { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let result = values.withUnsafeMutableBytes { buffer in AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer.baseAddress!) }
        guard result == noErr else { return nil }
        return Array(values.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }
    private static func number(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
    private static func name(_ object: AudioObjectID) -> String { string(object, selector: kAudioObjectPropertyName) }
    private static func string(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> String {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return "" }
        return value?.takeRetainedValue() as String? ?? ""
    }
}
