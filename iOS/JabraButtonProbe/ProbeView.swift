import SwiftUI

struct ProbeView: View {
    @Bindable var probe: HeadsetProbe
    @Environment(\.scenePhase) private var scenePhase
    @State private var report: ReportSnapshot?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Can iPhone see the Teams button?", systemImage: "headphones")
                        .font(.headline)
                    Text("This app collects evidence only. It does not remap buttons or start voice recording.")
                        .foregroundStyle(.secondary)
                    TextField("Headset model (optional)", text: $probe.headsetLabel)
                        .autocorrectionDisabled()
                }
                Section("1 · Pair with iPhone") {
                    Text("Pair your Jabra in iPhone Settings → Bluetooth first. Keep the headset on. Test away from calls, and initially disconnect its Mac/PC link so that button presses are not routed there.")
                    LabeledContent("Audio output", value: probe.routeSummary)
                        .font(.subheadline)
                    Button("Refresh audio & accessories", systemImage: "arrow.clockwise") {
                        probe.refreshRoute()
                        probe.refreshAccessories()
                    }
                    Text(probe.accessorySummary).font(.caption).foregroundStyle(.secondary)
                }
                bluetoothSection
                Section("3 · Optional media-button test") {
                    Text("Plays a quiet test tone for up to 2 minutes and listens for iOS media commands. It may pause other audio. Check that you hear the tone in the headset.")
                    if probe.mediaTestActive {
                        Label(probe.tonePlaying ? "Test tone playing" : "Test tone paused", systemImage: probe.tonePlaying ? "waveform" : "pause.circle")
                        if !probe.tonePlaying {
                            Button("Resume test tone") { probe.resumeTone() }
                        }
                        Button("Stop media test", role: .destructive) { probe.stopMediaTest() }
                    } else {
                        Button("Start media test", systemImage: "play.circle") { probe.startMediaTest() }
                    }
                    Text("Media commands do not identify which physical button sent them. Avoid Control Center and other remotes during trials.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                trialSection
                Section("Evidence") {
                    NavigationLink {
                        EventLogView(probe: probe)
                    } label: {
                        Label("Live event log (\(probe.evidence.events.count))", systemImage: "list.bullet.rectangle")
                    }
                    if let last = probe.evidence.events.last {
                        Text("Latest: \(last.message)").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    Text("No event means no signal was observed through these APIs. It does not rule out a vendor-specific solution. BLE notifications can also be battery/status updates.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Stop all tests", role: .destructive) { probe.stopAll() }
                }
            }
            .navigationTitle("Jabra Button Probe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Report", systemImage: "square.and.arrow.up") {
                        report = ReportSnapshot(text: probe.exportReport())
                    }
                }
            }
            .sheet(item: $report) { ReportView(report: $0) }
            .onChange(of: scenePhase) { _, phase in
                probe.sceneChanged(String(describing: phase))
            }
        }
    }

    private var bluetoothSection: some View {
        Section("2 · Look for a button signal over BLE") {
            LabeledContent("Bluetooth", value: probe.bluetoothStatus).font(.subheadline)
            Text("Scan, then connect only to your headset. If it is missing, try its pairing mode and scan again. A working audio connection does not guarantee a visible BLE interface.")
            if probe.scanning {
                HStack {
                    ProgressView()
                    Text("Scanning for 30 seconds…")
                    Spacer()
                    Button("Stop") { probe.stopScan() }
                }
            } else {
                Button("Scan Bluetooth LE", systemImage: "antenna.radiowaves.left.and.right") { probe.startScan() }
            }
            ForEach(probe.nearby) { device in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(device.name).font(.headline)
                        Spacer()
                        if probe.selectedID == device.id {
                            Image(systemName: probe.connected ? "checkmark.circle.fill" : "ellipsis.circle")
                                .foregroundStyle(.tint)
                        } else {
                            Button("Connect") { probe.connect(device.id) }
                                .buttonStyle(.bordered)
                                .disabled(probe.selectedID != nil)
                        }
                    }
                    Text(device.id.uuidString).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    Text(device.detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            if probe.nearby.isEmpty {
                Text("No BLE devices listed yet.").foregroundStyle(.secondary)
            }
            LabeledContent("Selected device", value: probe.connectionStatus).font(.subheadline)
            if probe.selectedID != nil {
                LabeledContent("Notification subscriptions", value: "\(probe.subscriptionCount)")
                Button("Disconnect BLE") { probe.disconnect() }
            }
        }
    }

    private var trialSection: some View {
        Section("4 · Compare 12-second trials") {
            Text("Run idle without touching anything. Next, run Teams and press/release Teams three times, about 2 seconds apart. Finally, test play/pause three times. Repeat to check consistency.")
            if probe.evidence.activeTrialID != nil {
                Label("Trial running · \(probe.trialSecondsLeft)s left", systemImage: "timer")
                    .font(.headline).foregroundStyle(.tint)
            }
            ForEach(TrialKind.allCases) { kind in
                Button("Test: \(kind.rawValue)") { probe.startTrial(kind) }
                    .disabled(probe.evidence.activeTrialID != nil || (!probe.connected && !probe.mediaTestActive))
            }
            ForEach(probe.evidence.trials.suffix(6).reversed()) { trial in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(trial.kind.rawValue).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(trial.interrupted ? "Interrupted" : (trial.finished ? "Complete" : "Running"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("BLE: \(trial.notifications) · Media: \(trial.mediaCommands)")
                        .font(.caption.monospaced())
                }
            }
        }
    }
}

private struct EventLogView: View {
    var probe: HeadsetProbe
    var body: some View {
        List(probe.evidence.events.reversed()) { event in
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(event.kind.rawValue.uppercased()).font(.caption.weight(.bold))
                        .foregroundStyle(event.kind.isButtonCandidate ? Color.blue : Color.secondary)
                    Spacer()
                    Text(event.date, format: .dateTime.hour().minute().second().secondFraction(.fractional(3)))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(event.message).font(.caption.monospaced()).textSelection(.enabled)
            }
        }
        .navigationTitle("Live events")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReportSnapshot: Identifiable {
    let id = UUID()
    let text: String
}

private struct ReportView: View {
    let report: ReportSnapshot
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Review before sharing. This report can include nearby device names, Bluetooth identifiers and raw characteristic values.")
                        .font(.callout).foregroundStyle(.secondary)
                    ShareLink(item: report.text) {
                        Label("Share diagnostic report", systemImage: "square.and.arrow.up")
                    }.buttonStyle(.borderedProminent)
                    Text(report.text).font(.caption.monospaced()).textSelection(.enabled)
                }.padding()
            }
            .navigationTitle("Diagnostic report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

#Preview { ProbeView(probe: HeadsetProbe()) }
