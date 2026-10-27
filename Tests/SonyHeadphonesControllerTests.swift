import XCTest
@testable import XM5Control

@MainActor
final class SonyHeadphonesControllerTests: XCTestCase {
    @MainActor private final class Clock {
        struct Entry { let time: Double; let action: @MainActor () -> Void; var cancelled = false }
        var now = 0.0
        var entries: [UUID: Entry] = [:]
        func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> () -> Void {
            let id = UUID()
            entries[id] = Entry(time: now + delay, action: action)
            return { self.entries[id]?.cancelled = true }
        }
        func advance(_ duration: Double, includingCancelled: Bool = false) {
            let end = now + duration
            while let next = entries.filter({ $0.value.time <= end }).min(by: { $0.value.time < $1.value.time }) {
                entries.removeValue(forKey: next.key)
                now = next.value.time
                if !next.value.cancelled || includingCancelled { next.value.action() }
            }
            now = end
        }
    }
    private final class Transport { var payloads: [[UInt8]] = [] }
    private func makeController() -> (SonyHeadphonesController, Clock, Transport) {
        let clock = Clock(), transport = Transport()
        let controller = SonyHeadphonesController(writePayload: { transport.payloads.append($0) }, schedule: clock.schedule)
        controller.setReconnectAutomatically(false)
        return (controller, clock, transport)
    }
    @discardableResult
    private func ready(_ c: SonyHeadphonesController, model: SonyHeadphoneModel = .whXM6, functions: [UInt8] = [0x6D, 0x20, 0x57]) -> UUID {
        let id = c.replaceSession(model: model, address: "A")
        c.beginHandshake(sessionID: id)
        c.handleIncomingPayload([1, 0, 0, 0, 0, 2, 0, 1], sessionID: id)
        c.handleIncomingPayload([7, 0, UInt8(functions.count)] + functions.flatMap { [$0, 0] }, sessionID: id)
        c.handleIncomingPayload([0x67, 0x19, 1, 1, 1, 0, 10, 1, 2], sessionID: id)
        if functions.contains(0x57) || model != .whXM6 {
            let count = model == .whXM6 ? 10 : 6
            c.handleIncomingPayload([0x57, 0, 0xA0, UInt8(count)] + Array(repeating: model == .whXM6 ? 6 : 10, count: count), sessionID: id)
        }
        return id
    }

    func testHandshakeValidatesProtocolAndPublishesCapabilities() {
        let (c, clock, t) = makeController()
        ready(c)
        XCTAssertTrue(c.isReady)
        XCTAssertEqual(c.model, .whXM6)
        XCTAssertEqual(c.protocolVersion, 2)
        XCTAssertEqual(c.equalizerSpecification?.id, .xm6TenBand)
        XCTAssertEqual(c.ambientLevel, 10)
        XCTAssertEqual(t.payloads.prefix(3), [[0, 0], [6, 0], [0x66, 0x19]])
        clock.advance(8)
        XCTAssertTrue(c.isReady)
        XCTAssertNil(c.lastErrorMessage)
    }
    func testMissingOrUnknownHandshakeHasBoundedFailure() {
        let (c, clock, _) = makeController()
        let id = c.replaceSession(model: .whXM6, address: "A")
        c.beginHandshake(sessionID: id)
        clock.advance(8)
        XCTAssertFalse(c.isReady)
        XCTAssertTrue(c.lastErrorMessage?.contains("timed out") == true)
        let second = c.replaceSession(model: .whXM6, address: "A")
        c.beginHandshake(sessionID: second)
        c.handleIncomingPayload([1, 0, 0, 0, 0, 3, 0, 1], sessionID: second)
        XCTAssertTrue(c.lastErrorMessage?.contains("Unsupported") == true)
    }
    func testConnectedCandidateAndSessionReplacementClearOldState() {
        let (c, _, _) = makeController()
        let old = ready(c, model: .whXM5)
        c.handleIncomingPayload([0x23, 0, 78, 1], sessionID: old)
        c.handleIncomingPayload([5, 2] + Array("2.5.1".utf8), sessionID: old)
        let selected = c.selectDevice(from: [
            .init(address: "A", name: "WH-1000XM5", model: .whXM5, isConnected: false),
            .init(address: "B", name: "WH-1000XM6", model: .whXM6, isConnected: true),
        ])
        XCTAssertEqual(selected?.address, "B")
        XCTAssertEqual(c.model, .whXM6)
        XCTAssertNil(c.batteryLevel)
        XCTAssertFalse(c.isCharging)
        XCTAssertNil(c.firmwareVersion)
        XCTAssertNil(c.equalizerPreset)
        XCTAssertNil(c.lastSyncDate)
        c.handleIncomingPayload([0x23, 0, 78, 1], sessionID: old)
        XCTAssertNil(c.batteryLevel)
    }
    func testUnsupportedAndInvalidEQLeaveNoiseAndBatteryUsable() {
        let (c, clock, t) = makeController()
        let id = ready(c, functions: [0x6D, 0x20])
        XCTAssertTrue(c.isReady)
        XCTAssertNil(c.equalizerSpecification)
        XCTAssertNotNil(c.equalizerUnavailableReason)
        c.handleIncomingPayload([0x23, 0, 80, 0], sessionID: id)
        XCTAssertEqual(c.batteryLevel, 80)
        c.refresh(); c.refreshEqualizer()
        XCTAssertFalse(t.payloads.contains([0x56, 0]))
        clock.advance(8)
        XCTAssertTrue(c.isReady)
        let second = ready(c)
        c.handleIncomingPayload([0x57, 0, 0xA0, 6, 10, 10, 10, 10, 10, 10], sessionID: second)
        XCTAssertNil(c.equalizerSpecification)
        XCTAssertTrue(c.isReady)
    }
    func testCustomEQRequiresReadbackAndNeverOptimisticallyChangesConfirmedState() {
        let (c, clock, t) = makeController()
        let id = ready(c)
        var curve = EqualizerSettings.flat(for: .xm6TenBand)
        curve[band: 0] = 3
        c.setCustomEqualizer(curve)
        XCTAssertTrue(c.isApplyingChange)
        XCTAssertEqual(c.customEqualizer, .flat(for: .xm6TenBand))
        clock.advance(0.12)
        XCTAssertEqual(t.payloads.last, [0x58, 0, 0xA0, 10, 9, 6, 6, 6, 6, 6, 6, 6, 6, 6])
        c.handleIncomingPayload([0x59, 0, 0xA0, 10, 9, 6, 6, 6, 6, 6, 6, 6, 6, 6], sessionID: id)
        XCTAssertTrue(c.isApplyingChange, "Notification is not a query response")
        clock.advance(0.25)
        XCTAssertEqual(t.payloads.last, [0x56, 0])
        c.handleIncomingPayload([0x57, 0, 0xA0, 10, 9, 6, 6, 6, 6, 6, 6, 6, 6, 6], sessionID: id)
        XCTAssertFalse(c.isApplyingChange)
        XCTAssertEqual(c.customEqualizer, curve)
        XCTAssertNil(c.lastErrorMessage)
    }
    func testRapidEditsSupersedePendingConfirmationAndTimeoutDoesNotClaimSuccess() {
        let (c, clock, _) = makeController()
        let id = ready(c)
        var curve = EqualizerSettings.flat(for: .xm6TenBand)
        curve[band: 0] = 1
        c.setCustomEqualizer(curve)
        clock.advance(0.12)
        curve[band: 0] = 2
        c.setCustomEqualizer(curve)
        clock.advance(0.12)
        clock.advance(0.25)
        c.handleIncomingPayload([0x57, 0, 0xA0, 10, 7, 6, 6, 6, 6, 6, 6, 6, 6, 6], sessionID: id)
        XCTAssertTrue(c.isApplyingChange)
        clock.advance(3)
        XCTAssertFalse(c.isApplyingChange)
        XCTAssertNotNil(c.lastErrorMessage)
        XCTAssertEqual(c.customEqualizer.bands[0], 1, "Keep actual readback, never the unconfirmed local value")
    }
    func testNoiseControlConfirmsOnlyItsOwnReadbackAndPreservesAdaptiveFields() {
        let (c, clock, t) = makeController()
        let id = ready(c)
        c.applyPreset(mode: .ambient, ambientLevel: 8, focusOnVoice: true)
        XCTAssertEqual(c.ambientLevel, 10)
        XCTAssertEqual(t.payloads.last, [0x68, 0x19, 1, 1, 1, 1, 8, 1, 2])
        clock.advance(0.25)
        c.handleIncomingPayload([0x57, 0, 0xA0, 0], sessionID: id)
        XCTAssertTrue(c.isApplyingChange)
        c.handleIncomingPayload([0x67, 0x19, 1, 1, 1, 1, 8, 1, 2], sessionID: id)
        XCTAssertFalse(c.isApplyingChange)
        XCTAssertEqual(c.ambientLevel, 8)
        XCTAssertTrue(c.focusOnVoice)
    }
    func testOldScheduledWorkCannotSendOrMutateNewSessionEvenIfCancellationRaces() {
        let (c, clock, t) = makeController()
        ready(c)
        c.setCustomEqualizer(.flat(for: .xm6TenBand))
        c.setAmbientLevel(18)
        c.replaceSession(model: .whXM5, address: "B")
        let count = t.payloads.count
        clock.advance(10, includingCancelled: true)
        XCTAssertEqual(t.payloads.count, count)
        XCTAssertFalse(c.isApplyingChange)
        XCTAssertNil(c.noiseControlMode)
        XCTAssertEqual(c.customEqualizer.layout, .xm5SixValue)
    }
    func testDisconnectCancelsPendingWritesAndRejectsWrongLayout() {
        let (c, clock, t) = makeController()
        let id = ready(c)
        let count = t.payloads.count
        c.setCustomEqualizer(.flat)
        XCTAssertEqual(t.payloads.count, count)
        XCTAssertFalse(c.isApplyingChange)
        c.setCustomEqualizer(.flat(for: .xm6TenBand))
        c.controlLinkClosed(sessionID: id)
        clock.advance(4, includingCancelled: true)
        XCTAssertEqual(t.payloads.count, count)
        XCTAssertFalse(c.isReady)
        XCTAssertNil(c.equalizerPreset)
        XCTAssertNil(c.pendingEqualizer)
    }
    func testDelayedAReadbackCannotConfirmRejectedReplacementAAfterB() {
        let (c, clock, t) = makeController()
        let id = ready(c)
        var a = EqualizerSettings.flat(for: .xm6TenBand)
        a[band: 0] = 1
        var b = a; b[band: 0] = 2
        c.setCustomEqualizer(a); clock.advance(0.12); clock.advance(0.25)
        c.setCustomEqualizer(b); clock.advance(0.12)
        c.setCustomEqualizer(a); clock.advance(0.12); clock.advance(0.25)
        let queries = t.payloads.filter { $0 == [0x56, 0] }.count
        c.handleIncomingPayload([0x57,0,0xA0,10,7,6,6,6,6,6,6,6,6,6], sessionID: id)
        XCTAssertTrue(c.isApplyingChange, "The delayed first A query must not confirm the replacement A operation")
        XCTAssertEqual(t.payloads.filter { $0 == [0x56,0] }.count, queries + 1, "Drain the old query before issuing the replacement's readback")
        c.handleIncomingPayload([0x57,0,0xA0,10,8,6,6,6,6,6,6,6,6,6], sessionID: id)
        clock.advance(3)
        XCTAssertFalse(c.isApplyingChange)
        XCTAssertNotNil(c.lastErrorMessage)
        XCTAssertEqual(c.customEqualizer, b)
    }
    func testDelayedNoiseReadbackCannotConfirmReplacementOperation() {
        let (c, clock, _) = makeController()
        let id = ready(c)
        c.setNoiseControl(.anc); clock.advance(0.25)
        c.setNoiseControl(.ambient)
        c.setNoiseControl(.anc); clock.advance(0.25)
        c.handleIncomingPayload([0x67,0x19,1,1,0,0,10,1,2], sessionID: id)
        XCTAssertTrue(c.isApplyingChange)
        c.handleIncomingPayload([0x67,0x19,1,1,1,0,10,1,2], sessionID: id)
        clock.advance(3)
        XCTAssertNotNil(c.lastErrorMessage)
        XCTAssertEqual(c.noiseControlMode, .ambient)
    }
    func testPeriodicQueryCannotConfirmAnOperationAndMissingReplyRequiresResync() {
        let (c, clock, _) = makeController()
        let id = ready(c)
        c.refresh()
        c.setCustomEqualizer(.flat(for: .xm6TenBand)); clock.advance(0.12); clock.advance(0.25)
        c.handleIncomingPayload([0x57,0,0xA0,10,6,6,6,6,6,6,6,6,6,6], sessionID: id)
        XCTAssertTrue(c.isApplyingChange, "An earlier manual/poll query is not this operation's readback")
        clock.advance(3)
        XCTAssertNotNil(c.lastErrorMessage)
        c.refresh()
        XCTAssertNotEqual(c.sessionID, id, "An unanswered query cannot be reassigned to a new operation")
        c.handleIncomingPayload([0x57,0,0xA0,10,6,6,6,6,6,6,6,6,6,6], sessionID: id)
        XCTAssertFalse(c.isReady)
    }
    func testPresetOnlyCustomNeverEstablishesAReportedCurve() {
        let (c, _, _) = makeController()
        let id = ready(c)
        XCTAssertTrue(c.hasReportedEqualizerCurve)
        c.handleIncomingPayload([0x57,0,0xA0,0], sessionID: id)
        XCTAssertEqual(c.equalizerPreset?.rawValue, 0xA0)
        XCTAssertFalse(c.hasReportedEqualizerCurve)
        c.handleIncomingPayload([0x57,0,0x30,10,7,6,6,6,6,6,6,6,6,6], sessionID: id)
        XCTAssertTrue(c.hasReportedEqualizerCurve)
        c.handleIncomingPayload([0x57,0,0xA0,0], sessionID: id)
        XCTAssertFalse(c.hasReportedEqualizerCurve, "Do not reuse another preset's curve")
    }

    func testMissingInitialEQStopsPollingItAfterTimeout() {
        let (c, clock, t) = makeController()
        let id = c.replaceSession(model: .whXM6, address: "A")
        c.beginHandshake(sessionID: id)
        c.handleIncomingPayload([1,0,0,0,0,2,0,1], sessionID: id)
        c.handleIncomingPayload([7,0,2,0x6D,0,0x57,0], sessionID: id)
        c.handleIncomingPayload([0x67,0x19,1,1,0,0,10,0,0], sessionID: id)
        clock.advance(3)
        XCTAssertTrue(c.isReady)
        XCTAssertNil(c.equalizerSpecification)
        let count = t.payloads.filter { $0 == [0x56,0] }.count
        c.refresh()
        XCTAssertEqual(t.payloads.filter { $0 == [0x56,0] }.count, count)
    }
}
