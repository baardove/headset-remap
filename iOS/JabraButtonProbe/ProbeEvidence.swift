import Foundation

enum EventKind: String {
    case status, discovery, service, read, notification, media, route, marker, error

    var isButtonCandidate: Bool { self == .notification || self == .media }
}

struct ProbeEvent: Identifiable {
    let id = UUID()
    let date: Date
    let kind: EventKind
    let message: String
}

enum TrialKind: String, CaseIterable, Identifiable {
    case idle = "Idle baseline"
    case teams = "Teams button"
    case control = "Play/pause control"
    var id: String { rawValue }
}

struct ProbeTrial: Identifiable {
    let id = UUID()
    let kind: TrialKind
    let start: Date
    let end: Date
    let context: String
    var notifications = 0
    var mediaCommands = 0
    var interrupted = false
    var finished = false
}

/// Foundation-only evidence logic: reads/discovery never count as button candidates.
struct ProbeEvidence {
    private(set) var events: [ProbeEvent] = []
    private(set) var trials: [ProbeTrial] = []
    private(set) var droppedEvents = 0
    private(set) var activeTrialID: UUID?
    let maximumEvents: Int

    init(maximumEvents: Int = 600) { self.maximumEvents = max(1, maximumEvents) }

    mutating func append(_ kind: EventKind, _ message: String, at date: Date = Date()) {
        finishExpired(at: date)
        events.append(ProbeEvent(date: date, kind: kind, message: message))
        if events.count > maximumEvents {
            droppedEvents += events.count - maximumEvents
            events.removeFirst(events.count - maximumEvents)
        }
        guard let id = activeTrialID,
              let i = trials.firstIndex(where: { $0.id == id }),
              date >= trials[i].start, date < trials[i].end else { return }
        if kind == .notification { trials[i].notifications += 1 }
        if kind == .media { trials[i].mediaCommands += 1 }
    }

    @discardableResult
    mutating func start(_ kind: TrialKind, context: String, at date: Date = Date(), duration: TimeInterval = 12) -> Bool {
        finishExpired(at: date)
        guard activeTrialID == nil else { return false }
        let trial = ProbeTrial(kind: kind, start: date, end: date.addingTimeInterval(duration), context: context)
        trials.append(trial)
        activeTrialID = trial.id
        append(.marker, "START \(kind.rawValue), \(Int(duration)) seconds; \(context)", at: date)
        return true
    }

    mutating func finishExpired(at date: Date = Date()) {
        guard let id = activeTrialID, let i = trials.firstIndex(where: { $0.id == id }), date >= trials[i].end else { return }
        trials[i].finished = true
        activeTrialID = nil
    }

    mutating func interrupt(at date: Date = Date()) {
        finishExpired(at: date)
        guard let id = activeTrialID, let i = trials.firstIndex(where: { $0.id == id }) else { return }
        trials[i].interrupted = true
        trials[i].finished = true
        activeTrialID = nil
    }

    func report(header: String, at date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines = ["Jabra Button Probe — iOS feasibility report", "Exported: \(formatter.string(from: date))", header,
            "", "INTERPRETATION",
            "Notification/media events are candidates, not proof that Teams caused them.",
            "Compare idle, Teams and control trials on the physical headset, and repeat.",
            "No signal only means none was observed through these public APIs in this session.",
            "BLE discovery does not expose raw Bluetooth Classic/USB HID. This app uses no private APIs.",
            "ExternalAccessory lists only accessories/protocols visible to this app. Empty is inconclusive.",
            "No microphone recording, voice launch, firmware commands or characteristic-value writes.",
            "BLE notification subscriptions are enabled only on the device you select.",
            "Names, Bluetooth identifiers, protocol UUIDs and raw values may appear below.",
            "", "TRIALS"]
        if trials.isEmpty { lines.append("No trials run.") }
        for trial in trials {
            let state = trial.interrupted ? "interrupted" : (trial.finished || date >= trial.end ? "completed" : "in progress")
            lines.append("\(formatter.string(from: trial.start)) | \(trial.kind.rawValue) | \(state) | BLE notifications=\(trial.notifications), media commands=\(trial.mediaCommands) | \(trial.context)")
        }
        lines += ["", "EVENTS (oldest first; \(droppedEvents) older events omitted)"]
        lines += events.map { "\(formatter.string(from: $0.date)) [\($0.kind.rawValue)] \($0.message)" }
        return lines.joined(separator: "\n")
    }
}
