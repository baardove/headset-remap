import XCTest
@testable import JabraButtonProbe

final class ProbeEvidenceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1000)

    func testReadsAndDiscoveryDoNotBecomeButtonEvidence() {
        var evidence = ProbeEvidence()
        evidence.start(.teams, context: "test", at: start)
        evidence.append(.read, "battery", at: start.addingTimeInterval(1))
        evidence.append(.discovery, "device", at: start.addingTimeInterval(2))
        evidence.append(.notification, "candidate", at: start.addingTimeInterval(3))
        evidence.append(.media, "toggle", at: start.addingTimeInterval(4))
        XCTAssertEqual(evidence.trials[0].notifications, 1)
        XCTAssertEqual(evidence.trials[0].mediaCommands, 1)
    }

    func testTrialBoundariesExcludeLateEvents() {
        var evidence = ProbeEvidence()
        evidence.start(.teams, context: "test", at: start)
        evidence.append(.notification, "early", at: start.addingTimeInterval(-1))
        evidence.append(.notification, "inside", at: start.addingTimeInterval(11.999))
        evidence.append(.notification, "boundary", at: start.addingTimeInterval(12))
        XCTAssertEqual(evidence.trials[0].notifications, 1)
        XCTAssertTrue(evidence.trials[0].finished)
        XCTAssertNil(evidence.activeTrialID)
    }

    func testCannotOverlapTrialsButCanStartAfterExpiration() {
        var evidence = ProbeEvidence()
        XCTAssertTrue(evidence.start(.idle, context: "a", at: start))
        XCTAssertFalse(evidence.start(.teams, context: "b", at: start.addingTimeInterval(2)))
        XCTAssertTrue(evidence.start(.teams, context: "b", at: start.addingTimeInterval(12)))
        XCTAssertEqual(evidence.trials.count, 2)
    }

    func testDisconnectInterruptsTrialAndLaterEventsAreExcluded() {
        var evidence = ProbeEvidence()
        evidence.start(.teams, context: "test", at: start)
        evidence.interrupt(at: start.addingTimeInterval(2))
        evidence.append(.notification, "late", at: start.addingTimeInterval(3))
        XCTAssertTrue(evidence.trials[0].interrupted)
        XCTAssertTrue(evidence.trials[0].finished)
        XCTAssertEqual(evidence.trials[0].notifications, 0)
    }

    func testBoundedLogRetainsTrialTotals() {
        var evidence = ProbeEvidence(maximumEvents: 2)
        evidence.start(.teams, context: "test", at: start)
        for i in 1...5 { evidence.append(.notification, "\(i)", at: start.addingTimeInterval(Double(i))) }
        XCTAssertEqual(evidence.events.count, 2)
        XCTAssertEqual(evidence.droppedEvents, 4)
        XCTAssertEqual(evidence.trials[0].notifications, 5)
    }

    func testReportPreservesLimitationsAndTrialContext() {
        var evidence = ProbeEvidence()
        evidence.start(.idle, context: "Evolve3; media off", at: start)
        let report = evidence.report(header: "test phone", at: start.addingTimeInterval(15))
        XCTAssertTrue(report.contains("candidates, not proof"))
        XCTAssertTrue(report.contains("Evolve3; media off"))
        XCTAssertTrue(report.contains("completed"))
        XCTAssertTrue(report.contains("media commands=0"))
    }

    func testGeneratedToneIsOneSecondMonoPCM() {
        let data = TestTone.wav()
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(data.count, 44 + 22050 * 2)
        XCTAssertTrue(data.dropFirst(44).contains { $0 != 0 })
    }
}
