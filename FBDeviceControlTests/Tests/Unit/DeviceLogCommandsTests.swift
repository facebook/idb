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

private let syslogRelay = "com.apple.syslog_relay"

/// Everything `tailLog` asks of the AMDevice. The session is opened only for long enough to start
/// the service, so it is closed while the connection the caller reads from is still open.
private let syslogSessionEvents = [
  "connect",
  "is_paired",
  "validate_pairing",
  "start_session",
  "secure_start_service:\(syslogRelay)",
  "stop_session",
  "disconnect",
]

/// `tailLog` returns an operation and the connection behind it stays live until the caller is
/// finished with that operation, so the service connection outlives the call that opened it.
///
/// Pinned on the main actor: the fake records its calls from the device's work and async queues,
/// both of which are the main queue, so the assertions have to read them from the same one.
@MainActor
@Suite(.serialized)
final class DeviceLogCommandsTests {

  private let amDevice = FakeAMDevice()
  private let device: FBDevice

  init() {
    device = amDevice.makeDevice()
  }

  private var syslog: FakeLockdownService {
    amDevice.service(syslogRelay)
  }

  /// Teardown is enqueued on the device's work queue when the operation completes, so it can still
  /// be pending when the await that triggered it resumes.
  private func waitFor(
    _ description: String,
    timeout: TimeInterval = 5,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
  ) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline, !condition() {
      try? await Task.sleep(nanoseconds: 20_000_000)
    }
    if !condition() {
      Issue.record("Timed out after \(timeout)s waiting for \(description)", sourceLocation: sourceLocation)
    }
  }

  @Test
  func tailLog_ReadsTheSyslogRelayIntoTheConsumer() async throws {
    syslog.readBuffer = Data("a line of syslog\n".utf8)
    let consumer = FBDataBuffer.accumulatingBuffer()

    let operation = try await device.tailLog(arguments: [], consumer: consumer)
    _ = try await bridgeFBFuture(consumer.finishedConsuming)

    #expect((String(decoding: consumer.data(), as: UTF8.self)) == ("a line of syslog\n"))
    #expect((operation.consumer) === (consumer))
    await waitFor("the AMDevice session to close") { self.amDevice.events == syslogSessionEvents }
    #expect((syslogSessionEvents) == (amDevice.events))
  }

  /// The device reaching the end of its log leaves the operation running and the connection open:
  /// only the caller decides when tailing ends. The AMDevice session that started the service is
  /// already closed by then.
  @Test
  func tailLog_LeavesTheConnectionOpenWhenTheDeviceStopsWriting() async throws {
    let consumer = FBDataBuffer.accumulatingBuffer()

    let operation = try #require(try await device.tailLog(arguments: [], consumer: consumer) as? DeviceLogOperation)
    _ = try await bridgeFBFuture(consumer.finishedConsuming)
    await waitFor("the AMDevice session to close") { self.amDevice.events == syslogSessionEvents }

    #expect((operation.completed.state) == (.running))
    #expect(!syslog.isInvalidated)
  }

  /// The companion's log handler cancels the wait exactly this way when the client goes away.
  @Test
  func tailLog_InvalidatesTheConnectionWhenTheWaitIsCancelled() async throws {
    let consumer = FBDataBuffer.accumulatingBuffer()
    let operation = try await device.tailLog(arguments: [], consumer: consumer)
    await waitFor("the AMDevice session to close") { self.amDevice.events == syslogSessionEvents }
    #expect(!syslog.isInvalidated)

    let waiting = Task { try await operation.waitUntilCompleted() }
    waiting.cancel()
    await #expect(throws: CancellationError.self) { try await waiting.value }

    await waitFor("the service connection to be invalidated") { self.syslog.isInvalidated }
    // Invalidation is all that is left to do: the session was released when the service started.
    #expect((syslogSessionEvents) == (amDevice.events))
  }
}
