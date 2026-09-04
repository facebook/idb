/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBDeviceControl
import Foundation
import Testing

/// The AMDevice calls a single `withConnectedDevice` scope makes on the way in, and on the way out.
private let sessionStart = ["connect", "is_paired", "validate_pairing", "start_session"]
private let sessionEnd = ["stop_session", "disconnect"]

/// Holds every scope open until all `expected` have arrived, so overlap is asserted via
/// `peakArrivals` rather than left to the scheduler: the AMDevice call trace alone cannot tell
/// overlapping scopes from serialised ones. The timeout only turns a serialising regression into a
/// `peakArrivals` failure instead of a hang.
///
/// `@unchecked Sendable`: all mutable state is guarded by `lock`.
private final class ScopeBarrier: @unchecked Sendable {

  private let expected: Int
  private let timeout: TimeInterval
  private let lock = NSLock()
  private var waiting: [CheckedContinuation<Void, Never>] = []
  private var released = false
  private var peak = 0

  init(expected: Int, timeout: TimeInterval = 2) {
    self.expected = expected
    self.timeout = timeout
  }

  /// The most callers that were ever parked here at once, which is `expected` only if they really
  /// were inside their scopes together.
  var peakArrivals: Int {
    lock.lock()
    defer { lock.unlock() }
    return peak
  }

  func arriveAndWait() async {
    let timer = Task { [weak self, timeout] in
      try? await Task.sleep(nanoseconds: UInt64(timeout * Double(NSEC_PER_SEC)))
      self?.releaseAll()
    }
    await withCheckedContinuation { continuation in
      lock.lock()
      if released {
        lock.unlock()
        continuation.resume()
        return
      }
      waiting.append(continuation)
      peak = max(peak, waiting.count)
      let isLastToArrive = waiting.count == expected
      lock.unlock()
      guard isLastToArrive else {
        return
      }
      releaseAll()
    }
    timer.cancel()
  }

  private func releaseAll() {
    lock.lock()
    released = true
    let all = waiting
    waiting.removeAll()
    lock.unlock()
    for continuation in all {
      continuation.resume()
    }
  }
}

/// A device session is opened for the duration of a `withConnectedDevice` scope, but scopes nest
/// and overlap (`withHouseArrestAFCConnection` opens one around work that opens more), so the
/// session is reference counted: overlapping scopes share one and only the last to end closes it.
@MainActor
// Serialized: the fake device's queues are the main queue, so parallel tests would interleave on it.
@Suite("Device connection scopes", .serialized)
struct FBDeviceConnectionScopeTests {

  private let amDevice = FakeAMDevice()

  /// A scope's teardown is enqueued on the device's work queue as the scope unwinds, so it can
  /// still be pending when the `await` on the scope resumes.
  private func waitForEvents(
    _ expected: [String],
    timeout: TimeInterval = 5,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline, amDevice.events != expected {
      try? await Task.sleep(nanoseconds: 20_000_000)
    }
    #expect(amDevice.events == expected, sourceLocation: sourceLocation)
  }

  @Test("One scope opens one session and closes it")
  func oneScopeOpensAndClosesOneSession() async throws {
    let device = amDevice.makeAMDevice()

    let value = try await device.withConnectedDevice(purpose: "test") { connected in
      #expect(connected === device, "the body is handed the connected device")
      #expect(amDevice.events == sessionStart, "the session is open for the duration of the body")
      return 42
    }

    #expect(value == 42)
    await waitForEvents(sessionStart + sessionEnd)
  }

  /// No connection reuse timeout is configured — production builds every device that way — so
  /// nothing is pooled between scopes and each pays for its own session.
  @Test("Sequential scopes each open their own session")
  func sequentialScopesEachOpenTheirOwnSession() async throws {
    let device = amDevice.makeAMDevice()

    for _ in 0..<2 {
      try await device.withConnectedDevice(purpose: "test") { _ in }
    }

    await waitForEvents(sessionStart + sessionEnd + sessionStart + sessionEnd)
  }

  @Test("Overlapping scopes share one session")
  func overlappingScopesShareOneSession() async throws {
    let device = amDevice.makeAMDevice()
    let barrier = ScopeBarrier(expected: 3)

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<3 {
        group.addTask { @MainActor in
          try? await device.withConnectedDevice(purpose: "test") { _ in
            await barrier.arriveAndWait()
          }
        }
      }
    }

    #expect(barrier.peakArrivals == 3, "all three scopes are open at once, not admitted in turn")
    await waitForEvents(sessionStart + sessionEnd)
  }

  @Test("A throwing body still closes the session")
  func aThrowingBodyStillClosesTheSession() async {
    struct BodyError: Error {}
    let device = amDevice.makeAMDevice()

    await #expect(throws: BodyError.self) {
      try await device.withConnectedDevice(purpose: "test") { _ in throw BodyError() }
    }

    await waitForEvents(sessionStart + sessionEnd)
  }

  /// A scope whose session cannot be opened fails rather than running its body, and leaves no
  /// session open for the next one to inherit. `AMDeviceStartSession` failing disconnects on the
  /// way out of the pairing sequence itself, which is why there is a `disconnect` with no
  /// preceding `stop_session`.
  @Test("A failed session leaves nothing open and does not poison the next scope")
  func aFailedSessionLeavesNothingOpenAndDoesNotPoisonTheNextScope() async throws {
    let device = amDevice.makeAMDevice()
    amDevice.startSessionStatus = -1

    var bodyRan = false
    do {
      try await device.withConnectedDevice(purpose: "test") { _ in bodyRan = true }
      Issue.record("Expected the failure to open a session to surface")
    } catch {
      #expect(error.localizedDescription.contains("Failed to start session with device"))
    }
    #expect(bodyRan == false)

    let failedStart = ["connect", "is_paired", "validate_pairing", "start_session", "disconnect"]
    await waitForEvents(failedStart)

    amDevice.startSessionStatus = 0
    try await device.withConnectedDevice(purpose: "test") { _ in }

    await waitForEvents(failedStart + sessionStart + sessionEnd)
  }

  @Test("Overlapping scopes share one session when one body throws")
  func overlappingScopesShareOneSessionWhenOneBodyThrows() async throws {
    struct BodyError: Error {}
    let device = amDevice.makeAMDevice()
    let barrier = ScopeBarrier(expected: 3)

    let completed = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
      for index in 0..<3 {
        group.addTask { @MainActor in
          let succeeded: Bool? = try? await device.withConnectedDevice(purpose: "test") { _ in
            await barrier.arriveAndWait()
            if index == 0 {
              throw BodyError()
            }
            return true
          }
          return succeeded ?? false
        }
      }
      return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
    }

    #expect(completed == 2)
    #expect(barrier.peakArrivals == 3, "all three scopes are open at once, not admitted in turn")
    await waitForEvents(sessionStart + sessionEnd)
  }
}

/// Separate from `FBDeviceConnectionScopeTests` because it must not be main-actor. That suite runs
/// its scopes one at a time on one thread, so the window in which a session is part way through
/// being opened never exists there — the first caller runs the connect to completion before any
/// other gets a turn. On a device the connect takes as long as the hardware takes, and callers
/// really do arrive inside it.
@Suite("Device session opening", .serialized)
struct FBAMDeviceSessionOpeningTests {

  /// The case the reference count cannot express on its own: a caller that arrives before there is
  /// anything to count. It has to wait for the connect already in flight and then share it, rather
  /// than reading "no session" and starting a second one.
  @Test("A caller arriving while the session is opening waits for it and shares it")
  func aCallerArrivingWhileOpeningSharesTheSession() async throws {
    let amDevice = FakeAMDevice()
    // Held for the duration: the session refers to its device weakly.
    let device = amDevice.makeAMDevice()
    defer { withExtendedLifetime(device) {} }
    let session = device.session

    let connectStarted = DispatchSemaphore(value: 0)
    // A latch rather than a hand-off: it stays open once opened, so a second connect runs to
    // completion and is caught by the assertion instead of deadlocking the test.
    let letConnectFinish = DispatchSemaphore(value: 0)
    amDevice.onConnect = {
      connectStarted.signal()
      letConnectFinish.wait()
      letConnectFinish.signal()
    }

    let opener = Task.detached { try await session.acquire() }
    connectStarted.wait()

    // The connect is now held part way through, so the session is provably `opening` and this
    // caller cannot see it in any other state.
    let joiner = Task.detached { try await session.acquire() }
    try await Task.sleep(nanoseconds: 200_000_000)
    letConnectFinish.signal()

    try await opener.value
    try await joiner.value

    #expect(amDevice.events == sessionStart, "one connect between the two of them")

    session.release()
    #expect(amDevice.events == sessionStart, "the joiner still holds it")

    session.release()
    #expect(amDevice.events == sessionStart + sessionEnd, "torn down once, after the last of them")
  }

  /// A connect takes as long as the device takes, so a caller waiting on someone else's has to be
  /// able to give up. It leaves with nothing — no share of the session, and so nothing to release.
  @Test("A caller cancelled while waiting for the session stops waiting and takes no share")
  func aCancelledWaiterStopsWaitingAndTakesNoShare() async throws {
    let amDevice = FakeAMDevice()
    // Held for the duration: the session refers to its device weakly.
    let device = amDevice.makeAMDevice()
    defer { withExtendedLifetime(device) {} }
    let session = device.session

    let connectStarted = DispatchSemaphore(value: 0)
    let letConnectFinish = DispatchSemaphore(value: 0)
    amDevice.onConnect = {
      connectStarted.signal()
      letConnectFinish.wait()
      letConnectFinish.signal()
    }

    let opener = Task.detached { try await session.acquire() }
    connectStarted.wait()

    let joiner = Task.detached { try await session.acquire() }
    try await Task.sleep(nanoseconds: 200_000_000)
    joiner.cancel()
    // Let the connect finish before awaiting the joiner, so that a regression which ignores the
    // cancellation is resumed by the session opening and fails the expectation below, rather than
    // staying parked and hanging the suite.
    letConnectFinish.signal()

    await #expect(throws: CancellationError.self) {
      try await joiner.value
    }

    try await opener.value
    #expect(amDevice.events == sessionStart, "one connect, and none from the caller that left")

    // The opener is the only user left, so its release is the last one and closes the session. Were
    // the cancelled caller still counted, this would leave the session open.
    session.release()
    #expect(amDevice.events == sessionStart + sessionEnd, "torn down on the opener's release alone")
  }
}
