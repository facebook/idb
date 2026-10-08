/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorAX
import FBSimulatorBridgeProtocol
@testable import FBSimulatorControl
import Foundation
import XCTest

final class AXBridgeQuiescenceTests: XCTestCase {

  private func automation(_ transport: any AXBridgeTransport) -> AXBridgeUIAutomation {
    AXBridgeUIAutomation(
      simulator: SimulatorTestSupport.testableSimulator(withDevice: AXBridgeQuiescenceDevice()),
      transport: transport,
      persistence: .exclusive)
  }

  // An unencodable fixture yields an empty frame, which fails the test as unparseable.
  private static func frame(_ object: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
  }

  private static func state(_ state: String, pid: pid_t = 42, signals: [String]? = nil) -> Data {
    var object: [String: Any] = ["ok": true, "event": "state", "state": state, "pid": Int(pid)]
    object["signals"] = signals
    return frame(object)
  }

  private func events(_ stream: AsyncThrowingStream<QuiescenceEvent, Error>) async throws -> [QuiescenceEvent] {
    var events: [QuiescenceEvent] = []
    for try await event in stream {
      events.append(event)
    }
    return events
  }

  func testEveryEventDecodes() async throws {
    let transport = StubAXBridgeStreamingTransport(frames: [
      Self.state("busy", signals: ["animations_inactive", "run_loop_idle"]),
      Self.state("settling"),
      Self.state("quiet"),
      Self.frame(["ok": true, "event": "touches_completed", "pid": 42]),
      Self.frame(["ok": true, "event": "target_changed", "pid": 43]),
      Self.frame(["ok": true, "event": "target_exited", "pid": 43]),
    ])
    let events = try await events(automation(transport).quiescence(.frontmost, parameters: QuiescenceParameters()))
    XCTAssertEqual(
      events,
      [
        .state(.busy([.animationsInactive, .runLoopIdle]), pid: 42),
        .state(.settling, pid: 42),
        .state(.quiet, pid: 42),
        .touchesCompleted(pid: 42),
        .targetChanged(pid: 43),
        .targetExited(pid: 43),
      ])
  }

  func testTheRequestCarriesThePidAndTheTunablesInMilliseconds() async throws {
    let transport = StubAXBridgeStreamingTransport(frames: [])
    _ = try await events(
      automation(transport).quiescence(.application(pid: 7), parameters: QuiescenceParameters(busyThreshold: 0.05, quietWindow: 1.5)))
    let request = await transport.requests.first
    let payload = try XCTUnwrap(request?.payload as? [String: AnyHashable])
    XCTAssertEqual(payload, ["verb": "quiet", "pid": 7, "busyThresholdMs": 50, "quietWindowMs": 1500])
  }

  func testTheFrontmostRequestLeavesThePidAndDefaultsToTheGuest() async throws {
    let transport = StubAXBridgeStreamingTransport(frames: [])
    _ = try await events(automation(transport).quiescence(.frontmost, parameters: QuiescenceParameters()))
    let request = await transport.requests.first
    let payload = try XCTUnwrap(request?.payload as? [String: AnyHashable])
    XCTAssertEqual(payload, ["verb": "quiet"])
  }

  func testAnApplicationFailureIsTranslated() async throws {
    let transport = StubAXBridgeStreamingTransport(frames: [
      Self.frame(["ok": false, "error": "gone", "error_kind": "application_unavailable", "pid": 7])
    ])
    do {
      _ = try await events(automation(transport).quiescence(.application(pid: 7), parameters: QuiescenceParameters()))
      XCTFail("expected a failure")
    } catch let UIAutomationError.applicationUnavailable(_, pid) {
      XCTAssertEqual(pid, 7)
    }
  }

  func testAPointOrMarkerIsRefused() async throws {
    let transport = StubAXBridgeStreamingTransport(frames: [])
    for query: AccessibilityElementQuery in [.point(.zero), .marker(value: "x", key: .label, depth: 1)] {
      do {
        _ = try await automation(transport).quiescence(query, parameters: QuiescenceParameters())
        XCTFail("expected \(query) to be refused")
      } catch UIAutomationError.operationUnsupported {}
    }
    let requests = await transport.requests
    XCTAssertTrue(requests.isEmpty)
  }

  func testATransportThatCannotStreamIsRefused() async throws {
    do {
      _ = try await automation(AXBridgeOneshotTransport(simulator: SimulatorTestSupport.testableSimulator(withDevice: AXBridgeQuiescenceDevice())))
        .quiescence(.frontmost, parameters: QuiescenceParameters())
      XCTFail("expected a failure")
    } catch UIAutomationError.operationUnsupported {}
  }

  func testTheCurrentStateSkipsSettling() async throws {
    let transport = StubAXBridgeStreamingTransport(frames: [
      Self.frame(["ok": true, "event": "touches_completed", "pid": 42]),
      Self.state("settling"),
      Self.state("busy", signals: ["run_loop_idle"]),
      Self.state("quiet"),
    ])
    var seen: [QuiescenceEvent] = []
    let current = try await automation(transport).quiescenceState(.frontmost) { seen.append($0) }
    XCTAssertEqual(current.state, .busy([.runLoopIdle]))
    XCTAssertEqual(current.pid, 42)
    XCTAssertEqual(seen, [.touchesCompleted(pid: 42), .state(.settling, pid: 42), .state(.busy([.runLoopIdle]), pid: 42)])
  }

  func testWaitingReturnsOnceQuietAndClosesTheStream() async throws {
    let transport = StubAXBridgeStreamingTransport(frames: [Self.state("busy", signals: ["run_loop_idle"]), Self.state("quiet")], holdsOpen: true)
    let seen = SeenQuiescenceEvents()
    let pid = try await automation(transport).waitForQuiet(.frontmost, timeout: 30) { seen.append($0) }
    XCTAssertEqual(pid, 42)
    XCTAssertEqual(seen.events, [.state(.busy([.runLoopIdle]), pid: 42), .state(.quiet, pid: 42)])
    try await transport.waitUntilTerminated()
  }

  func testWaitingTimesOutWithTheLastState() async throws {
    let transport = StubAXBridgeStreamingTransport(frames: [Self.state("busy", signals: ["animations_inactive"])], holdsOpen: true)
    do {
      _ = try await automation(transport).waitForQuiet(.frontmost, timeout: 0.1)
      XCTFail("expected a timeout")
    } catch let error as QuiescenceError {
      XCTAssertEqual(error, .timedOut(timeout: 0.1, last: .busy([.animationsInactive])))
      XCTAssertEqual(error.localizedDescription, "the application was not quiet within 0.1s; it was last busy (animations_inactive)")
    }
    try await transport.waitUntilTerminated()
  }

  // The last state was the previous target's, so it says nothing about the one now followed.
  func testWaitingThatTimesOutAfterTheTargetChangesHasNoLastState() async throws {
    let transport = StubAXBridgeStreamingTransport(
      frames: [Self.state("busy", signals: ["run_loop_idle"]), Self.frame(["ok": true, "event": "target_changed", "pid": 43])],
      holdsOpen: true)
    do {
      _ = try await automation(transport).waitForQuiet(.frontmost, timeout: 0.1)
      XCTFail("expected a timeout")
    } catch let error as QuiescenceError {
      XCTAssertEqual(error, .timedOut(timeout: 0.1, last: nil))
    }
    try await transport.waitUntilTerminated()
  }

  func testWaitingWithoutATimeoutReturnsOnceQuiet() async throws {
    let transport = StubAXBridgeStreamingTransport(frames: [Self.state("settling"), Self.state("quiet")], holdsOpen: true)
    let pid = try await automation(transport).waitForQuiet(.frontmost, timeout: nil)
    XCTAssertEqual(pid, 42)
    try await transport.waitUntilTerminated()
  }

  // A caller that goes away, as a cancelled RPC does, closes the stream rather than holding the guest.
  func testCancellingAWaitWithoutATimeoutClosesTheStream() async throws {
    let transport = StubAXBridgeStreamingTransport(frames: [Self.state("busy", signals: ["run_loop_idle"])], holdsOpen: true)
    let automation = automation(transport)
    let (busy, sawBusy) = AsyncStream<Void>.makeStream()
    let wait = Task { try await automation.waitForQuiet(.frontmost, timeout: nil) { _ in sawBusy.yield() } }
    for await _ in busy { break }
    wait.cancel()
    do {
      _ = try await wait.value
      XCTFail("expected the wait to be cancelled")
    } catch is CancellationError {}
    try await transport.waitUntilTerminated()
  }

  func testCancellingTheConsumerOfTheEventsClosesTheStream() async throws {
    let transport = StubAXBridgeStreamingTransport(frames: [Self.state("settling")], holdsOpen: true)
    let events = try await automation(transport).quiescence(.frontmost, parameters: QuiescenceParameters())
    let (settling, sawSettling) = AsyncStream<Void>.makeStream()
    let consumer = Task {
      for try await _ in events { sawSettling.yield() }
    }
    for await _ in settling { break }
    consumer.cancel()
    _ = await consumer.result
    try await transport.waitUntilTerminated()
  }

  func testWatchingReportsEveryEventPastQuietAndReturnsTheLastState() async throws {
    let transport = StubAXBridgeStreamingTransport(frames: [Self.state("quiet"), Self.state("busy", signals: ["run_loop_idle"])], holdsOpen: true)
    let seen = SeenQuiescenceEvents()
    let last = try await automation(transport).watchQuiescence(.frontmost, duration: 0.1) { seen.append($0) }
    XCTAssertEqual(last, .busy([.runLoopIdle]))
    XCTAssertEqual(seen.events, [.state(.quiet, pid: 42), .state(.busy([.runLoopIdle]), pid: 42)])
    try await transport.waitUntilTerminated()
  }

  func testWatchingThatEndsAfterTheTargetChangesHasNoLastState() async throws {
    let transport = StubAXBridgeStreamingTransport(
      frames: [Self.state("quiet"), Self.frame(["ok": true, "event": "target_changed", "pid": 43])],
      holdsOpen: true)
    let last = try await automation(transport).watchQuiescence(.frontmost, duration: 0.1) { _ in }
    XCTAssertNil(last)
    try await transport.waitUntilTerminated()
  }

  func testWatchingWithoutADurationRunsUntilCancelled() async throws {
    let transport = StubAXBridgeStreamingTransport(frames: [Self.state("quiet")], holdsOpen: true)
    let automation = automation(transport)
    let (quiet, sawQuiet) = AsyncStream<Void>.makeStream()
    let watch = Task { try await automation.watchQuiescence(.frontmost, duration: nil) { _ in sawQuiet.yield() } }
    for await _ in quiet { break }
    watch.cancel()
    do {
      _ = try await watch.value
      XCTFail("expected the watch to be cancelled")
    } catch is CancellationError {}
    try await transport.waitUntilTerminated()
  }

  func testWatchingAnApplicationThatExitsFails() async throws {
    let transport = StubAXBridgeStreamingTransport(frames: [Self.state("quiet", pid: 7), Self.frame(["ok": true, "event": "target_exited", "pid": 7])])
    do {
      _ = try await automation(transport).watchQuiescence(.application(pid: 7), duration: 30) { _ in }
      XCTFail("expected a failure")
    } catch let error as QuiescenceError {
      XCTAssertEqual(error, .targetExited(pid: 7))
    }
  }

  func testWaitingForAnApplicationThatExitsFails() async throws {
    let transport = StubAXBridgeStreamingTransport(frames: [Self.frame(["ok": true, "event": "target_exited", "pid": 7])])
    do {
      _ = try await automation(transport).waitForQuiet(.application(pid: 7), timeout: 30)
      XCTFail("expected a failure")
    } catch let error as QuiescenceError {
      XCTAssertEqual(error, .targetExited(pid: 7))
    }
  }

  // MARK: - Following the active display

  private func automation(_ transport: FollowingTransport, displays: DisplayCommandsDouble, selection: DisplaySelection = .active) -> AXBridgeUIAutomation {
    AXBridgeUIAutomation(
      simulator: SimulatorTestSupport.testableSimulator(withDevice: AXBridgeQuiescenceDevice()),
      transport: transport,
      persistence: .exclusive,
      displays: displays,
      selection: selection)
  }

  private static func display(_ uniqueID: String, rotation: SimulatorDisplayRotation = .upright) -> SimulatorDisplayTarget {
    .selected(
      SimulatorDisplay(
        uniqueID: uniqueID, name: uniqueID, activity: .active, isPrimary: false, isIntegrated: true,
        bounds: CGRect(x: 0, y: 0, width: 1200, height: 800), scale: 2, rotation: rotation))
  }

  private static let inventory = [
    SimulatorAccessibilityDisplay(uniqueID: "inner", displayID: 82),
    SimulatorAccessibilityDisplay(uniqueID: "cover", displayID: 83),
  ]

  private func events(_ stream: AsyncThrowingStream<QuiescenceEvent, Error>, count: Int) async throws -> [QuiescenceEvent] {
    var events: [QuiescenceEvent] = []
    for try await event in stream {
      events.append(event)
      if events.count == count { break }
    }
    return events
  }

  func testFollowingTheFrontmostNamesTheActiveDisplay() async throws {
    let transport = FollowingTransport(inventory: Self.inventory, streams: [[Self.state("quiet")]])
    let stream = try await automation(transport, displays: DisplayCommandsDouble(Self.display("inner")))
      .quiescence(.frontmost, parameters: QuiescenceParameters())
    let events = try await events(stream, count: 1)
    XCTAssertEqual(events, [.state(.quiet, pid: 42)])
    let requests = await transport.streamRequests
    XCTAssertEqual(requests.map { $0.payload["displayID"] as? UInt32 }, [82])
  }

  func testASwitchToAnotherDisplayReopensTheStreamThereAndReportsTheNewTarget() async throws {
    let transport = FollowingTransport(inventory: Self.inventory, streams: [[Self.state("quiet")], [Self.state("busy", pid: 43, signals: ["run_loop_idle"])]])
    let displays = DisplayCommandsDouble(Self.display("inner"), Self.display("inner"), Self.display("cover"))
    let stream = try await automation(transport, displays: displays).quiescence(.frontmost, parameters: QuiescenceParameters())
    let events = try await events(stream, count: 3)
    XCTAssertEqual(events, [.state(.quiet, pid: 42), .targetChanged(pid: 43), .state(.busy([.runLoopIdle]), pid: 43)])
    let requests = await transport.streamRequests
    XCTAssertEqual(requests.map { $0.payload["displayID"] as? UInt32 }, [82, 83])
    try await transport.waitUntilTerminated(streams: 1)
  }

  func testASwitchAwayFromASelectedDisplayEndsTheStream() async throws {
    let transport = FollowingTransport(inventory: Self.inventory, streams: [[Self.state("quiet")], [Self.state("busy", pid: 43)]])
    let displays = DisplayCommandsDouble(Self.display("inner"), Self.display("inner"), Self.display("cover"))
    let stream = try await automation(transport, displays: displays, selection: .display(uniqueID: "inner"))
      .quiescence(.frontmost, parameters: QuiescenceParameters())
    var events: [QuiescenceEvent] = []
    do {
      for try await event in stream { events.append(event) }
      XCTFail("Expected a display change")
    } catch { guard case SimulatorDisplayError.changed = error else { return XCTFail("\(error)") } }
    XCTAssertEqual(events, [.state(.quiet, pid: 42)])
    let requests = await transport.streamRequests
    XCTAssertEqual(requests.map { $0.payload["displayID"] as? UInt32 }, [82])
  }

  func testSelectingAnInactiveDisplayOpensNoStream() async throws {
    let transport = FollowingTransport(inventory: Self.inventory, streams: [[Self.state("quiet")]])
    do {
      _ = try await automation(transport, displays: DisplayCommandsDouble(Self.display("inner")), selection: .display(uniqueID: "cover"))
        .quiescence(.frontmost, parameters: QuiescenceParameters())
      XCTFail("Expected an inactive display")
    } catch { guard case SimulatorDisplayInteractionError.inactiveDisplay("cover") = error else { return XCTFail("\(error)") } }
    let requests = await transport.streamRequests
    XCTAssertTrue(requests.isEmpty)
  }

  func testASwitchThatKeepsTheSameApplicationDoesNotReportATargetChange() async throws {
    let transport = FollowingTransport(inventory: Self.inventory, streams: [[Self.state("quiet")], [Self.state("settling")]])
    let displays = DisplayCommandsDouble(Self.display("inner"), Self.display("inner"), Self.display("cover"))
    let stream = try await automation(transport, displays: displays).quiescence(.frontmost, parameters: QuiescenceParameters())
    let events = try await events(stream, count: 2)
    XCTAssertEqual(events, [.state(.quiet, pid: 42), .state(.settling, pid: 42)])
  }

  // The new display's application is reported as it arrives, not announced as a target it already left.
  func testASwitchThatOpensOnAnExitedApplicationDoesNotAnnounceIt() async throws {
    let transport = FollowingTransport(
      inventory: Self.inventory, streams: [[Self.state("quiet")], [Self.frame(["ok": true, "event": "target_exited", "pid": 43])]])
    let displays = DisplayCommandsDouble(Self.display("inner"), Self.display("inner"), Self.display("cover"))
    let stream = try await automation(transport, displays: displays).quiescence(.frontmost, parameters: QuiescenceParameters())
    let events = try await events(stream, count: 2)
    XCTAssertEqual(events, [.state(.quiet, pid: 42), .targetExited(pid: 43)])
  }

  // A switch the confirming read does not bear out as another named display leaves the stream scoped
  // where it is rather than reopening it unscoped.
  func testASwitchWithoutAnAccessibilityIdentityKeepsTheStreamWhereItIs() async throws {
    let transport = FollowingTransport(inventory: Self.inventory, streams: [[Self.state("quiet")]])
    guard case let .selected(cover) = Self.display("cover") else { return XCTFail("expected a selected display") }
    let displays = DisplayCommandsDouble(Self.display("inner"), Self.display("inner"), Self.display("cover"), .sole(.identified(cover)))
    let stream = try await automation(transport, displays: displays).quiescence(.frontmost, parameters: QuiescenceParameters())
    let consumer = Task { for try await _ in stream {} }
    while displays.reads < 5 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    consumer.cancel()
    _ = await consumer.result
    let requests = await transport.streamRequests
    XCTAssertEqual(requests.map { $0.payload["displayID"] as? UInt32 }, [82])
  }

  // A read mid-transition can fail, and a rotation changes only the geometry; neither moves the stream.
  func testAFailedReadOrARotationKeepsTheStreamWhereItIs() async throws {
    let transport = FollowingTransport(inventory: Self.inventory, streams: [[Self.state("quiet")]])
    let displays = DisplayCommandsDouble([
      .success(.reporting(Self.display("inner"))), .success(.reporting(Self.display("inner"))), .failure(SimulatorDisplayError.changed),
      .success(.reporting(Self.display("inner", rotation: .clockwise))),
    ])
    let stream = try await automation(transport, displays: displays).quiescence(.frontmost, parameters: QuiescenceParameters())
    let consumer = Task { for try await _ in stream {} }
    while displays.reads < 5 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    consumer.cancel()
    _ = await consumer.result
    let requests = await transport.streamRequests
    XCTAssertEqual(requests.count, 1)
  }

  func testAGuestThatCannotScopeQuiescenceIsRefusedOnSeveralDisplays() async throws {
    let transport = FollowingTransport(inventory: Self.inventory, streams: [], scopedQuiescence: false)
    do {
      _ = try await automation(transport, displays: DisplayCommandsDouble(Self.display("inner")))
        .quiescence(.frontmost, parameters: QuiescenceParameters())
      XCTFail("expected a failure")
    } catch SimulatorDisplayInteractionError.unsupportedCapability {}
    let requests = await transport.streamRequests
    XCTAssertTrue(requests.isEmpty)
  }

  func testANamedApplicationOrASoleDisplayIsNotRouted() async throws {
    let sole = SimulatorDisplayTarget.sole(.legacy(SimulatorDisplayGeometry(bounds: CGRect(x: 0, y: 0, width: 400, height: 800), scale: 2, rotation: .upright)))
    for (query, target) in [(AccessibilityElementQuery.application(pid: 7), Self.display("inner")), (.frontmost, sole)] {
      let transport = FollowingTransport(inventory: Self.inventory, streams: [[]], scopedQuiescence: false, holdsOpen: false)
      let displays = DisplayCommandsDouble(target)
      _ = try await events(automation(transport, displays: displays).quiescence(query, parameters: QuiescenceParameters()))
      let requests = await transport.streamRequests
      XCTAssertEqual(requests.count, 1)
      XCTAssertNil(requests.first?.payload["displayID"], "\(query)")
      XCTAssertEqual(displays.reads, query == .frontmost ? 1 : 0)
    }
  }

  func testWaitingOnAStreamThatEndsSilentlyFails() async throws {
    let transport = StubAXBridgeStreamingTransport(frames: [Self.state("settling")])
    do {
      _ = try await automation(transport).waitForQuiet(.frontmost, timeout: 30)
      XCTFail("expected a failure")
    } catch let error as QuiescenceError {
      XCTAssertEqual(error, .streamEnded)
    }
  }
}

// SAFETY: `recorded` is only read or written with `lock` held.
// patternlint-disable-next-line unchecked-sendable
private final class SeenQuiescenceEvents: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [QuiescenceEvent] = []

  var events: [QuiescenceEvent] { lock.withLock { recorded } }

  func append(_ event: QuiescenceEvent) {
    lock.withLock { recorded.append(event) }
  }
}

@objc private final class AXBridgeQuiescenceDevice: NSObject {
  @objc let UDID = NSUUID()
  @objc var deviceType: NSObject? { nil }
}

/// Yields `frames`, then either ends or, with `holdsOpen`, stays open until the consumer stops.
private actor StubAXBridgeStreamingTransport: AXBridgeStreamingTransport {
  private let frames: [Data]
  private let holdsOpen: Bool
  private(set) var requests: [AXBridgeRequest] = []
  private var terminated = false

  init(frames: [Data], holdsOpen: Bool = false) {
    self.frames = frames
    self.holdsOpen = holdsOpen
  }

  func send(_ request: AXBridgeRequest) async throws -> Data {
    throw AXBridgeError.bridgeUnavailable
  }

  func stream(_ request: AXBridgeRequest) async throws -> AsyncThrowingStream<Data, Error> {
    requests.append(request)
    let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
    continuation.onTermination = { _ in Task { await self.terminate() } }
    for frame in frames {
      continuation.yield(frame)
    }
    if !holdsOpen {
      continuation.finish()
    }
    return stream
  }

  private func terminate() {
    terminated = true
  }

  func waitUntilTerminated() async throws {
    let deadline = Date(timeIntervalSinceNow: 5)
    while !terminated {
      guard deadline.timeIntervalSinceNow > 0 else {
        throw AXBridgeError.guestFailure("the stream was never closed")
      }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
  }
}

/// Answers inventory requests with every display capability but, unless it is told otherwise, quiescence,
/// and opens each stream with the next scripted frames.
private actor FollowingTransport: AXBridgeStreamingTransport {
  private let inventory: [SimulatorAccessibilityDisplay]
  private var streams: [[Data]]
  private let scopedQuiescence: Bool
  private let holdsOpen: Bool
  private(set) var streamRequests: [AXBridgeRequest] = []
  private var terminated = 0

  init(inventory: [SimulatorAccessibilityDisplay], streams: [[Data]], scopedQuiescence: Bool = true, holdsOpen: Bool = true) {
    self.inventory = inventory
    self.streams = streams
    self.scopedQuiescence = scopedQuiescence
    self.holdsOpen = holdsOpen
  }

  func send(_ request: AXBridgeRequest) async throws -> Data {
    let displays = inventory.map { ["uniqueID": $0.uniqueID, "displayID": $0.displayID] as [String: Any] }
    return try JSONSerialization.data(withJSONObject: [
      "ok": true, "displayScopedInteractions": true, "displayScopedTrees": true, "displayScopedQuiescence": scopedQuiescence,
      "displays": displays,
    ])
  }

  func stream(_ request: AXBridgeRequest) async throws -> AsyncThrowingStream<Data, Error> {
    streamRequests.append(request)
    let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
    continuation.onTermination = { _ in Task { await self.terminate() } }
    for frame in streams.isEmpty ? [] : streams.removeFirst() {
      continuation.yield(frame)
    }
    if !holdsOpen {
      continuation.finish()
    }
    return stream
  }

  private func terminate() {
    terminated += 1
  }

  func waitUntilTerminated(streams count: Int) async throws {
    let deadline = Date(timeIntervalSinceNow: 5)
    while terminated < count {
      guard deadline.timeIntervalSinceNow > 0 else {
        throw AXBridgeError.guestFailure("the stream was never closed")
      }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
  }
}
