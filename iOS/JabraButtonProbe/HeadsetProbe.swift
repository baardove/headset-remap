import AVFoundation
import CoreBluetooth
import ExternalAccessory
import MediaPlayer
import Observation
import UIKit

struct NearbyDevice: Identifiable {
    let id: UUID
    var name: String
    var detail: String
}

@MainActor
@Observable
// Core Bluetooth invokes both delegates on the central's explicit main queue.
final class HeadsetProbe: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private(set) var bluetoothStatus = "Not started"
    private(set) var scanning = false
    private(set) var nearby: [NearbyDevice] = []
    private(set) var connectionStatus = "No BLE device selected"
    private(set) var selectedID: UUID?
    private(set) var connected = false
    private(set) var subscriptionCount = 0
    private(set) var accessorySummary = "Not checked"
    private(set) var routeSummary = "Not checked"
    private(set) var mediaTestActive = false
    private(set) var tonePlaying = false
    private(set) var trialSecondsLeft = 0
    private(set) var evidence = ProbeEvidence()
    var headsetLabel = ""

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var selected: CBPeripheral?
    @ObservationIgnored private var pendingScan = false
    @ObservationIgnored private var scanTimeout: Timer?
    @ObservationIgnored private var connectionTimeout: Timer?
    @ObservationIgnored private var trialTimer: Timer?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var mediaTimeout: Timer?
    @ObservationIgnored private var commandTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .EAAccessoryDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccessories() }
        })
        observers.append(center.addObserver(forName: .EAAccessoryDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccessories() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.refreshRoute()
                if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                    self?.stopMediaTest(reason: "Audio device disconnected")
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                if let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                   type == AVAudioSession.InterruptionType.began.rawValue {
                    self?.stopMediaTest(reason: "Audio interrupted")
                }
            }
        })
        EAAccessoryManager.shared().registerForLocalNotifications()
        log(.status, "Session started. No microphone, speech recognition, remapping or network requests.")
        refreshAccessories()
        refreshRoute()
    }

    func log(_ kind: EventKind, _ message: String) {
        evidence.append(kind, message)
    }

    func refreshAccessories() {
        let accessories = EAAccessoryManager.shared().connectedAccessories
        accessorySummary = accessories.isEmpty ? "No accessories visible to this app" : "\(accessories.count) visible accessories"
        log(.status, "ExternalAccessory: \(accessorySummary). An empty list is inconclusive; this app declares no vendor protocol strings.")
        for accessory in accessories {
            log(.discovery, "Accessory: \(accessory.name); manufacturer=\(accessory.manufacturer); model=\(accessory.modelNumber); firmware=\(accessory.firmwareRevision); protocols=\(accessory.protocolStrings.joined(separator: ", "))")
        }
    }

    func refreshRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        routeSummary = outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
        if routeSummary.isEmpty { routeSummary = "No current output" }
        log(.route, routeSummary)
    }

    func startScan() {
        guard !scanning else { return }
        pendingScan = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else if central?.state == .poweredOn {
            beginScan()
        } else {
            pendingScan = false
            log(.error, "Cannot scan: \(bluetoothStatus). Allow Bluetooth in Settings and turn it on, then retry.")
        }
    }

    private func beginScan() {
        guard let central, central.state == .poweredOn else { return }
        pendingScan = false
        scanning = true
        log(.status, "BLE scan started (30 seconds). Classic Bluetooth audio devices may not advertise BLE.")
        // These standard services and a remembered selection are hints, not a complete list.
        let existing = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: "180A"), CBUUID(string: "180F"), CBUUID(string: "1812")])
        for peripheral in existing { remember(peripheral, detail: "Already connected to iOS; standard service hint") }
        if let string = UserDefaults.standard.string(forKey: "lastProbePeripheral"), let id = UUID(uuidString: string) {
            for peripheral in central.retrievePeripherals(withIdentifiers: [id]) {
                remember(peripheral, detail: "Previously selected; availability not confirmed")
            }
        }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimeout?.invalidate()
        scanTimeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopScan() }
        }
    }

    func stopScan() {
        pendingScan = false
        scanTimeout?.invalidate()
        central?.stopScan()
        if scanning { log(.status, "BLE scan stopped; \(nearby.count) devices listed.") }
        scanning = false
    }

    private func remember(_ peripheral: CBPeripheral, name: String? = nil, detail: String) {
        peripherals[peripheral.identifier] = peripheral
        let display = name ?? peripheral.name ?? "Unnamed BLE device"
        let device = NearbyDevice(id: peripheral.identifier, name: display, detail: detail)
        if let i = nearby.firstIndex(where: { $0.id == device.id }) {
            nearby[i] = device
        } else {
            nearby.append(device)
            nearby.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            log(.discovery, "BLE: \(display); id=\(device.id); \(detail)")
        }
    }

    func connect(_ id: UUID) {
        guard selected == nil, let central, central.state == .poweredOn, let peripheral = peripherals[id] else { return }
        interruptTrial("BLE selection changed")
        stopScan()
        selected = peripheral
        selectedID = id
        peripheral.delegate = self
        subscriptionCount = 0
        connectionStatus = "Connecting to \(peripheral.name ?? "selected device")…"
        log(.status, connectionStatus)
        central.connect(peripheral, options: nil)
        connectionTimeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.connected else { return }
                self.disconnect(reason: "BLE connection timed out")
            }
        }
    }

    func disconnect(reason: String = "Disconnected by user") {
        connectionTimeout?.invalidate()
        interruptTrial(reason)
        if let selected { central?.cancelPeripheralConnection(selected) }
        clearConnection()
        log(.status, reason)
    }

    private func clearConnection() {
        selected?.delegate = nil
        selected = nil
        selectedID = nil
        connected = false
        subscriptionCount = 0
        connectionStatus = "No BLE device selected"
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown: bluetoothStatus = "Initializing"
        case .resetting: bluetoothStatus = "Resetting"
        case .unsupported: bluetoothStatus = "BLE unavailable (simulators cannot test hardware)"
        case .unauthorized: bluetoothStatus = "Bluetooth permission denied"
        case .poweredOff: bluetoothStatus = "Bluetooth is off"
        case .poweredOn: bluetoothStatus = "Bluetooth is on"
        @unknown default: bluetoothStatus = "Unknown Bluetooth state"
        }
        log(.status, bluetoothStatus)
        if central.state == .poweredOn {
            if pendingScan { beginScan() }
        } else if central.state != .unknown {
            stopScan()
            if selected != nil { disconnect(reason: bluetoothStatus) }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
        let manufacturer = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data).map(hex) ?? "none"
        remember(peripheral, name: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
                 detail: "RSSI \(RSSI) dBm; services=\(services.joined(separator: ",")); manufacturer=\(manufacturer)")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral == selected else { central.cancelPeripheralConnection(peripheral); return }
        connectionTimeout?.invalidate()
        connected = true
        connectionStatus = "Connected: \(peripheral.name ?? "BLE device")"
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "lastProbePeripheral")
        log(.status, "\(connectionStatus). Discovering public GATT services.")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral == selected else { return }
        disconnect(reason: "BLE connection failed: \(error?.localizedDescription ?? "unknown error")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == selected else { return }
        disconnect(reason: "BLE disconnected: \(error?.localizedDescription ?? "link ended")")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral == selected else { return }
        if let error { log(.error, "Service discovery: \(error.localizedDescription)"); return }
        let services = peripheral.services ?? []
        log(.service, "Found \(services.count) GATT services. Reserved HID services may be hidden by iOS.")
        for service in services {
            log(.service, "Service \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral == selected else { return }
        if let error { log(.error, "Characteristics \(service.uuid): \(error.localizedDescription)"); return }
        for characteristic in service.characteristics ?? [] {
            let properties = characteristic.properties
            log(.service, "\(path(characteristic)); properties=0x\(String(properties.rawValue, radix: 16))")
            if canNotify(characteristic) {
                peripheral.setNotifyValue(true, for: characteristic)
            } else if properties.contains(.read) {
                // Do not mix read responses with notifications from the same characteristic.
                peripheral.readValue(for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == selected else { return }
        if let error { log(.error, "Subscribe \(path(characteristic)): \(error.localizedDescription)"); return }
        subscriptionCount = (peripheral.services ?? []).flatMap { $0.characteristics ?? [] }.filter(\.isNotifying).count
        log(.service, "\(path(characteristic)); notifications \(characteristic.isNotifying ? "ON" : "OFF"); active=\(subscriptionCount)")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == selected else { return }
        if let error { log(.error, "Value \(path(characteristic)): \(error.localizedDescription)"); return }
        log(canNotify(characteristic) ? .notification : .read,
            "\(peripheral.name ?? "BLE") \(path(characteristic)) = \(hex(characteristic.value ?? Data()))")
    }

    private func canNotify(_ c: CBCharacteristic) -> Bool {
        !c.properties.intersection([.notify, .indicate, .notifyEncryptionRequired, .indicateEncryptionRequired]).isEmpty
    }

    private func path(_ c: CBCharacteristic) -> String { "\(c.service?.uuid.uuidString ?? "?")/\(c.uuid.uuidString)" }
    private func hex(_ data: Data) -> String {
        data.prefix(128).map { String(format: "%02X", $0) }.joined(separator: " ") + (data.count > 128 ? " … (\(data.count) bytes)" : "")
    }

    func startMediaTest() {
        guard !mediaTestActive else { return }
        interruptTrial("Media test started")
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let tone = try AVAudioPlayer(data: TestTone.wav())
            tone.numberOfLoops = -1
            tone.prepareToPlay()
            guard tone.play() else { throw NSError(domain: "JabraProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test tone could not start"]) }
            player = tone
            mediaTestActive = true
            tonePlaying = true
            registerCommands()
            updateNowPlaying()
            refreshRoute()
            log(.status, "Media test started: quiet audible tone, stops after 2 minutes. Remote events can also come from Control Center, not only the headset.")
            mediaTimeout = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopMediaTest(reason: "Two-minute media test completed") }
            }
        } catch {
            log(.error, "Media test: \(error.localizedDescription)")
            stopMediaTest(reason: "Media test failed")
        }
    }

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()
        let commands: [(MPRemoteCommand, String)] = [
            (center.playCommand, "play"), (center.pauseCommand, "pause"),
            (center.togglePlayPauseCommand, "toggle play/pause"), (center.stopCommand, "stop"),
            (center.nextTrackCommand, "next track"), (center.previousTrackCommand, "previous track")
        ]
        for (command, name) in commands {
            command.isEnabled = true
            let target = command.addTarget { [weak self] _ in
                // Apple can deliver remote commands off-main. Accept only while the test is armed.
                DispatchQueue.main.async { self?.receiveMediaCommand(name) }
                return .success
            }
            commandTargets.append((command, target))
        }
    }

    private func receiveMediaCommand(_ name: String) {
        guard mediaTestActive else { return }
        log(.media, "Remote command: \(name). Source device/button is not identified by iOS.")
        switch name {
        case "play": tonePlaying = player?.play() ?? false
        case "pause": player?.pause(); tonePlaying = false
        case "toggle play/pause":
            if tonePlaying { player?.pause(); tonePlaying = false }
            else { tonePlaying = player?.play() ?? false }
        case "stop": stopMediaTest(reason: "Remote stop"); return
        default: break
        }
        updateNowPlaying()
    }

    func resumeTone() {
        guard mediaTestActive else { return }
        tonePlaying = player?.play() ?? false
        updateNowPlaying()
        log(.status, "Tone resumed from app (not a headset event)")
    }

    private func updateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Jabra Button Probe",
            MPMediaItemPropertyArtist: "Temporary button test",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: tonePlaying ? 1.0 : 0.0
        ]
    }

    func stopMediaTest(reason: String = "Media test stopped") {
        let wasActive = mediaTestActive
        if wasActive { interruptTrial(reason) }
        mediaTimeout?.invalidate()
        player?.stop()
        player = nil
        mediaTestActive = false
        tonePlaying = false
        for (command, target) in commandTargets { command.removeTarget(target); command.isEnabled = false }
        commandTargets.removeAll()
        if wasActive { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if wasActive { log(.status, reason) }
    }

    func startTrial(_ kind: TrialKind) {
        guard connected || mediaTestActive else { log(.error, "Connect a BLE device or start the media test first."); return }
        let context = "label=\(headsetLabel.isEmpty ? "unspecified" : headsetLabel); BLE=\(connectionStatus); subscriptions=\(subscriptionCount); media=\(mediaTestActive); tone=\(tonePlaying); route=\(routeSummary)"
        guard evidence.start(kind, context: context) else { return }
        trialSecondsLeft = 12
        trialTimer?.invalidate()
        trialTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.evidence.finishExpired()
                guard let id = self.evidence.activeTrialID, let trial = self.evidence.trials.first(where: { $0.id == id }) else {
                    self.trialSecondsLeft = 0
                    timer.invalidate()
                    self.log(.marker, "Trial ended. Counts are observations, not proof of Teams-button support.")
                    return
                }
                self.trialSecondsLeft = max(0, Int(ceil(trial.end.timeIntervalSinceNow)))
            }
        }
    }

    private func interruptTrial(_ reason: String) {
        guard evidence.activeTrialID != nil else { return }
        evidence.interrupt()
        trialTimer?.invalidate()
        trialSecondsLeft = 0
        log(.marker, "Trial interrupted: \(reason)")
    }

    func sceneChanged(_ state: String) { log(.status, "App state: \(state)") }

    func stopAll() {
        interruptTrial("Stopped all tests")
        stopScan()
        if selected != nil { disconnect() }
        stopMediaTest()
    }

    func exportReport() -> String {
        evidence.finishExpired()
        let device = UIDevice.current
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return evidence.report(header: "App: \(version); \(device.model); \(device.systemName) \(device.systemVersion)\nHeadset label: \(headsetLabel)\nBluetooth: \(bluetoothStatus)\nBLE: \(connectionStatus); subscriptions=\(subscriptionCount)\nOutput: \(routeSummary)\nAccessories: \(accessorySummary)")
    }
}
