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

/// Holds every scope open until all of them have arrived, so scopes that are meant to overlap
/// really do rather than being left to the scheduler — and so that the overlap can be asserted
/// instead of inferred.
///
/// `peakArrivals` is the assertion that matters. The AMDevice call trace cannot distinguish
/// overlapping scopes from serialised ones: a serialised second scope re-uses the context the
/// first left behind and so makes the same calls, in the same order, as one that shared it.
///
/// The timeout exists only so that a regression which serialises the scopes fails on
/// `peakArrivals` rather than hanging the suite.
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

/// How many AMDevice sessions a given pattern of scopes opens, and when each is torn down.
///
/// A device is connected and a session opened for the duration of a `withConnectedDevice` scope
/// and closed when it ends, but scopes nest and overlap — every device command opens one, and
/// `withHouseArrestAFCConnection` opens one around work that opens more. So the session is
/// reference counted: overlapping scopes share one, and only the last to end closes it. That is
/// the whole of what `FBFutureContextManager` does for `FBAMDevice`.
///
/// Pinned here, at `withConnectedDevice`, rather than at the manager that implements it today,
/// because this seam is what survives the manager's removal.
@MainActor
// Serialized: these tests drive an `FBAMDevice` whose work and async queues are the main queue,
// from main-actor tests. Run in parallel they interleave on that one queue, which is why the other
// device-driving suites in this target are serialized too.
@Suite("Device connection scopes", .serialized)
struct FBDeviceConnectionScopeTests {

  // Fresh per test: each test in a Swift Testing suite gets its own suite instance.
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

  /// The reference count itself: three scopes are open at once, they connect once between them,
  /// and the session is torn down once, after the last of them ends.
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

  /// A scope that throws releases its use of the session on the way out, the same as one that
  /// returns; the body's error is what surfaces.
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

  /// One of the overlapping scopes failing does not take the shared session with it: the other two
  /// run to completion on it and it is still torn down exactly once.
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
