import XCTest
@testable import BeyGramProxy

final class MihomoAutoSelectGateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)

    func testProbesBeforeAnyReport() {
        let gate = MihomoAutoSelectGate()
        XCTAssertTrue(gate.shouldProbe(now: start))
    }

    func testConnectedNeverProbes() {
        var gate = MihomoAutoSelectGate()
        gate.report(.connected, now: start)
        XCTAssertFalse(gate.shouldProbe(now: start.addingTimeInterval(600)))
    }

    func testConnectingProbesOnlyAfterHandover() {
        var gate = MihomoAutoSelectGate()
        gate.report(.connecting, now: start)
        XCTAssertFalse(gate.shouldProbe(now: start.addingTimeInterval(7.9)))
        XCTAssertTrue(gate.shouldProbe(now: start.addingTimeInterval(8)))
    }

    func testConnectingAndWaitingShareOneWait() {
        var gate = MihomoAutoSelectGate()
        gate.report(.connecting, now: start)
        gate.report(.waitingForNetwork, now: start.addingTimeInterval(5))
        XCTAssertTrue(gate.shouldProbe(now: start.addingTimeInterval(8)))
    }

    func testBackToConnectedAndAgainRestartsTheWait() {
        var gate = MihomoAutoSelectGate()
        gate.report(.connecting, now: start)
        gate.report(.connected, now: start.addingTimeInterval(3))
        gate.report(.connecting, now: start.addingTimeInterval(20))
        XCTAssertFalse(gate.shouldProbe(now: start.addingTimeInterval(25)))
        XCTAssertTrue(gate.shouldProbe(now: start.addingTimeInterval(28)))
    }

    func testNetworkChangeCancelsTheWaitOnlyWhileWaiting() {
        var gate = MihomoAutoSelectGate()
        gate.report(.connecting, now: start)
        gate.networkChanged(now: start.addingTimeInterval(6))
        XCTAssertFalse(gate.shouldProbe(now: start.addingTimeInterval(10)))
        XCTAssertTrue(gate.shouldProbe(now: start.addingTimeInterval(14)))

        var connected = MihomoAutoSelectGate()
        connected.report(.connected, now: start)
        connected.networkChanged(now: start.addingTimeInterval(5))
        XCTAssertFalse(connected.shouldProbe(now: start.addingTimeInterval(100)))
    }

    func testResetGoesBackToProbing() {
        var gate = MihomoAutoSelectGate()
        gate.report(.connected, now: start)
        gate.reset()
        XCTAssertTrue(gate.shouldProbe(now: start))
    }
}
