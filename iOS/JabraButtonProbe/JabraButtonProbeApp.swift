import SwiftUI

@main
struct JabraButtonProbeApp: App {
    @State private var probe = HeadsetProbe()
    var body: some Scene {
        WindowGroup { ProbeView(probe: probe) }
    }
}
