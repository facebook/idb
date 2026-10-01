/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import XCTest

final class SimulatorHIDOperationTests: XCTestCase {
  func testNestedGestureUsesOneDisplayBindingAndDrainsOnce() async throws {
    let recorder = Recorder()
    var operation = makeOperation(recorder)
    try await operation.send(.composite([.composite([.tapAt(x: 20, y: 30)])]))
    try await operation.finish(flushing: true)
    let events = await recorder.events
    XCTAssertEqual(events.map(\.0), [.touch(direction: .down, x: 20, y: 30), .touch(direction: .up, x: 20, y: 30)])
    XCTAssertEqual(events.compactMap(\.1), [display(), display()])
    let flushes = await recorder.flushes
    XCTAssertEqual(flushes, 1)
  }

  func testFallbackDeliversEventsWithoutADisplay() async throws {
    let recorder = Recorder()
    var operation = SimulatorHIDOperation(
      displays: DisplayCommandsDouble([.success(.failed(.unsupported("displayinfo")))]),
      deliver: { event, display in await recorder.record(event, display: display) },
      flush: {},
      reportCleanupError: { XCTFail("cleanup failed: \($0)") })
    try await operation.send(.tapAt(x: 20, y: 30))
    try await operation.finish(flushing: false)
    let events = await recorder.events
    XCTAssertEqual(events.map(\.0), [.touch(direction: .down, x: 20, y: 30), .touch(direction: .up, x: 20, y: 30)])
    XCTAssertEqual(events.compactMap(\.1), [])
  }

  func testNonFiniteTouchWithoutADisplay() async throws {
    let recorder = Recorder()
    var operation = SimulatorHIDOperation(
      displays: DisplayCommandsDouble([.success(.failed(.unsupported("displayinfo")))]),
      deliver: { event, display in await recorder.record(event, display: display) },
      flush: {},
      reportCleanupError: { XCTFail("cleanup failed: \($0)") })
    // BUG: without a display, a non-finite point reaches the transport instead of being rejected — flipped in the following commit
    try await operation.send(.tapAt(x: .nan, y: 30))
    try await operation.finish(flushing: false)
    let events = await recorder.events
    XCTAssertEqual(events.count, 2)
    for (event, _) in events {
      guard case let .touch(_, x, y, _) = event else { return XCTFail("unexpected event: \(event)") }
      XCTAssertTrue(x.isNaN)
      XCTAssertEqual(y, 30)
    }
  }

  func testDisplayTransitionReleasesOnOriginalTargetWithoutSendingToNewTarget() async throws {
    let recorder = Recorder()
    let observation = SimulatorHIDDisplayObservation()
    var operation = makeOperation(recorder, observation: observation)
    try await operation.send(.touch(direction: .down, x: 20, y: 30))
    observation.record(.success(display("cover", target: 9)), matching: display())
    observation.record(.success(display()), matching: display())
    do {
      try await operation.send(.touch(direction: .up, x: 20, y: 30))
      XCTFail("expected a changed-display error")
    } catch {
      guard case SimulatorDisplayError.changed = error else { return XCTFail("unexpected error: \(error)") }
      await operation.cleanup()
    }
    let events = await recorder.events
    XCTAssertEqual(events.map(\.0), [.touch(direction: .down, x: 20, y: 30), .touch(direction: .up, x: 20, y: 30)])
    XCTAssertEqual(events.compactMap(\.1), [display(), display()])
  }

  func testDisplayTransitionObservedMidGestureFailsAsAChangedDisplay() async throws {
    let recorder = Recorder()
    let observation = SimulatorHIDDisplayObservation()
    var operation = makeOperation(recorder, observation: observation)
    try await operation.send(.touch(direction: .down, x: 20, y: 30))
    observation.record(.failure(SimulatorDisplayError.transitioning), matching: display())
    do {
      try await operation.send(.touch(direction: .up, x: 20, y: 30))
      XCTFail("expected the gesture to fail")
    } catch {
      guard case SimulatorDisplayError.changed = error else { return XCTFail("unexpected error: \(error)") }
      await operation.cleanup()
    }
  }

  func testOffScreenMoveMidGesture() async throws {
    let recorder = Recorder()
    var operation = makeOperation(recorder)
    try await operation.send(.touch(direction: .down, x: 20, y: 30))
    // BUG: a finite point past the edge fails the gesture instead of being clamped to it — flipped in the following commit
    do {
      try await operation.send(.touch(direction: .down, x: -1, y: 30))
      XCTFail("expected invalid coordinates")
    } catch {
      guard case let SimulatorDisplayInteractionError.invalidPoint(point, bounds) = error else { return XCTFail("unexpected error: \(error)") }
      XCTAssertEqual(point, CGPoint(x: -1, y: 30))
      XCTAssertEqual(bounds, CGSize(width: 200, height: 300))
      XCTAssertEqual(error.localizedDescription, "Touch point (-1.0, 30.0) is outside the display's point bounds (200.0 x 300.0)")
      await operation.cleanup()
    }
    let events = await recorder.events
    XCTAssertEqual(events.map(\.0), [.touch(direction: .down, x: 20, y: 30), .touch(direction: .up, x: 20, y: 30)])
  }

  func testOffScreenTwoFingerTouchOnRotatedDisplay() async throws {
    let recorder = Recorder()
    await recorder.setDisplay(screen(rotation: .clockwise))
    var operation = makeOperation(recorder)
    let first = CGPoint(x: 20, y: 30)
    let second = CGPoint(x: 20, y: 250)
    // BUG: a finite point past the edge fails the gesture instead of being clamped to it — flipped in the following commit
    do {
      try await operation.send(.twoFingerTouch(direction: .down, finger1: first, finger2: second))
      XCTFail("expected invalid coordinates")
    } catch {
      guard case let SimulatorDisplayInteractionError.invalidPoint(point, bounds) = error else { return XCTFail("unexpected error: \(error)") }
      XCTAssertEqual(point, second)
      XCTAssertEqual(bounds, CGSize(width: 300, height: 200))
      await operation.cleanup()
    }
    let events = await recorder.events
    XCTAssertTrue(events.isEmpty)
  }

  func testNonFiniteTouchFailsWithoutDelivering() async throws {
    let recorder = Recorder()
    var operation = makeOperation(recorder)
    do {
      try await operation.send(.tapAt(x: .nan, y: 30))
      XCTFail("expected invalid coordinates")
    } catch {
      guard case let SimulatorDisplayInteractionError.invalidPoint(point, bounds) = error else { return XCTFail("unexpected error: \(error)") }
      XCTAssertTrue(point.x.isNaN)
      XCTAssertEqual(point.y, 30)
      XCTAssertEqual(bounds, CGSize(width: 200, height: 300))
      XCTAssertEqual(error.localizedDescription, "Touch point (nan, 30.0) is not a real position (x is NaN) within the display's point bounds (200.0 x 300.0)")
      await operation.cleanup()
    }
    let events = await recorder.events
    XCTAssertTrue(events.isEmpty)
  }

  func testFinalReadDetectsRotationAfterLastTouch() async throws {
    let recorder = Recorder()
    var operation = makeOperation(recorder)
    try await operation.send(.tapAt(x: 20, y: 30))
    await recorder.setDisplay(screen(rotation: .clockwise))
    do {
      try await operation.finish(flushing: true)
      XCTFail("expected the final display check to fail")
    } catch {
      guard case SimulatorDisplayError.changed = error else { return XCTFail("unexpected error: \(error)") }
    }
  }

  func testCancellationReleasesBothFingersAndDrainsOutsideCancelledTask() async throws {
    let recorder = Recorder()
    let entered = Gate()
    let first = CGPoint(x: 20, y: 30)
    let second = CGPoint(x: 50, y: 60)
    let task = Task {
      var operation = makeOperation(recorder)
      do {
        try await operation.send(.twoFingerTouch(direction: .down, finger1: first, finger2: second))
        await entered.open()
        try await Task.sleep(nanoseconds: 60_000_000_000)
      } catch {
        await operation.cleanup()
        throw error
      }
    }
    await entered.wait()
    task.cancel()
    do {
      try await task.value
      XCTFail("expected cancellation")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
    let events = await recorder.events
    XCTAssertEqual(
      events.map(\.0),
      [
        .twoFingerTouch(direction: .down, finger1: first, finger2: second),
        .twoFingerTouch(direction: .up, finger1: first, finger2: second),
      ])
    let cancelled = await recorder.cancelledDeliveries
    let flushes = await recorder.flushes
    XCTAssertEqual(cancelled, 0)
    XCTAssertEqual(flushes, 1)
  }

  func testCancellationDuringDisplayLookupDoesNotWrite() async throws {
    let recorder = Recorder()
    let entered = Gate()
    let release = Gate()
    await recorder.block(after: 0, until: release, entered: entered)
    let task = Task {
      var operation = makeOperation(recorder)
      do {
        try await operation.send(.tapAt(x: 20, y: 30))
      } catch {
        await operation.cleanup()
        throw error
      }
    }
    await entered.wait()
    task.cancel()
    await release.open()
    do {
      try await task.value
      XCTFail("expected cancellation")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
    let events = await recorder.events
    XCTAssertTrue(events.isEmpty)
  }

  func testSlowDisplayObservationDoesNotDelayTouchSamples() async throws {
    let recorder = Recorder()
    let release = Gate()
    await recorder.block(after: 1, until: release)
    recorder.identities.remember([SimulatorTouchscreen(displayUniqueID: "inner", digitizerTarget: 7)])
    let sent = expectation(description: "touch samples sent while observation is blocked")
    let task = Task {
      var operation = makeOperation(recorder)
      try await operation.send(.tapAt(x: 20, y: 30))
      sent.fulfill()
      try await operation.finish(flushing: true)
    }
    await fulfillment(of: [sent], timeout: 2)
    await release.open()
    try await task.value
    let events = await recorder.events
    XCTAssertEqual(events.count, 2)
  }

  func testLeaseExcludesConcurrentOperationAndCancelledWaiterDoesNotBlockNext() async throws {
    let lease = SimulatorHIDOperationLease()
    let entered = Gate()
    let release = Gate()
    let waiting = Gate()
    let first = Task {
      try await lease.withLease {
        await entered.open()
        await release.wait()
      }
    }
    await entered.wait()
    let cancelled = Task {
      await waiting.open()
      try await lease.withLease { XCTFail("cancelled waiter must not acquire the lease") }
    }
    await waiting.wait()
    cancelled.cancel()
    do {
      try await cancelled.value
      XCTFail("expected cancellation while waiting")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
    await release.open()
    try await first.value
    let value = try await lease.withLease { 42 }
    XCTAssertEqual(value, 42)
  }

  private func makeOperation(_ recorder: Recorder, observation: SimulatorHIDDisplayObservation = SimulatorHIDDisplayObservation()) -> SimulatorHIDOperation {
    SimulatorHIDOperation(
      displays: recorder,
      deliver: { event, display in
        await recorder.record(event, display: display)
      },
      flush: { await recorder.flush() },
      reportCleanupError: { XCTFail("cleanup failed: \($0)") },
      observation: observation)
  }

  private func display(_ identity: String = "inner", target: UInt32 = 7, rotation: SimulatorDisplayRotation = .upright) -> SimulatorHIDDisplay {
    .selected(screen(identity, rotation: rotation), target: target)
  }

  private func screen(_ identity: String = "inner", rotation: SimulatorDisplayRotation = .upright) -> SimulatorDisplay {
    Self.makeScreen(identity, rotation: rotation)
  }

  private static func makeScreen(_ identity: String = "inner", rotation: SimulatorDisplayRotation = .upright) -> SimulatorDisplay {
    SimulatorDisplay(
      uniqueID: identity, name: identity, activity: .active, isPrimary: true, isIntegrated: true,
      bounds: CGRect(x: 0, y: 0, width: 600, height: 900), scale: 3, rotation: rotation)
  }

  /// One of several displays, reached through digitizer target 7. Reads past `block(after:)` wait on the gate.
  private actor Recorder: DisplayCommands {
    nonisolated let identities = DisplayIdentityCache()
    var currentDisplay: SimulatorDisplay = SimulatorHIDOperationTests.makeScreen()
    var events: [(SimulatorHIDEvent, SimulatorHIDDisplay?)] = []
    var flushes = 0
    var cancelledDeliveries = 0
    private var reads = 0
    private var blocking: (after: Int, gate: Gate, entered: Gate?)?

    func block(after reads: Int, until gate: Gate, entered: Gate? = nil) {
      blocking = (reads, gate, entered)
    }

    func report() async throws -> SimulatorDisplayReport {
      reads += 1
      if let blocking, reads > blocking.after {
        await blocking.entered?.open()
        await blocking.gate.wait()
      }
      return .reporting(.selected(currentDisplay))
    }

    func touchscreens() -> [SimulatorTouchscreen] {
      [SimulatorTouchscreen(displayUniqueID: currentDisplay.uniqueID, digitizerTarget: 7)]
    }

    func setDisplay(_ display: SimulatorDisplay) { currentDisplay = display }
    func record(_ event: SimulatorHIDEvent, display: SimulatorHIDDisplay?) {
      events.append((event, display))
      if Task.isCancelled { cancelledDeliveries += 1 }
    }
    func flush() { flushes += 1 }
  }

  private actor Gate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
      if opened { return }
      await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
      opened = true
      let pending = waiters
      waiters = []
      for waiter in pending { waiter.resume() }
    }
  }
}
