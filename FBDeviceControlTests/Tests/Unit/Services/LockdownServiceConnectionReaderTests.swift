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

// MARK: - File-scope state for C function pointer callbacks

// Gate for the blocking-receive fake: receive blocks until invalidation signals it, mimicking a
// socket read unblocked by connection invalidation. File-scope because a C function pointer
// cannot capture; the suite is serialized so tests cannot race on it.
private var sReceiveGate = DispatchSemaphore(value: 0)

private func endOfFileReceive(_ connection: CFTypeRef?, _ buffer: UnsafeMutableRawPointer?, _ bytes: Int) -> Int32 {
  0
}

private func blockingReceive(_ connection: CFTypeRef?, _ buffer: UnsafeMutableRawPointer?, _ bytes: Int) -> Int32 {
  sReceiveGate.wait()
  return 0
}

private func invalidateUnblockingReceive(_ connection: CFTypeRef?) -> Int32 {
  sReceiveGate.signal()
  return 0
}

private func invalidateLeavingReceiveBlocked(_ connection: CFTypeRef?) -> Int32 {
  0
}

/// A connection reference that can be observed weakly, unlike a constant string.
private final class ConnectionReference {}

@Suite(.serialized)
struct LockdownServiceConnectionReaderTests {

  private func makeConnection(calls: AMDCalls, connection: AnyObject = "fake-connection-ref" as AnyObject) -> LockdownServiceConnection {
    LockdownServiceConnection(
      name: "test-connection",
      connection: connection,
      device: "fake-device-ref" as AnyObject,
      calls: calls,
      logger: ControlCoreGlobalConfiguration.defaultLogger)
  }

  @Test
  func readerDeliversEndOfFileToTheConsumer() async throws {
    var calls = CreateZeroedAMDCalls()
    calls.ServiceConnectionGetSecureIOContext = { _ in nil }
    calls.ServiceConnectionReceive = endOfFileReceive
    let connection = makeConnection(calls: calls)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let queue = DispatchQueue(label: "com.facebook.fbdevicecontrol.tests.reader")
    let reader = connection.readFromConnectionWriting(to: consumer, on: queue)

    _ = try await bridgeFBFuture(reader.startReading())
    _ = try await bridgeFBFuture(consumer.finishedConsuming)

    let finished = try await bridgeFBFuture(reader.finishedReading)
    #expect(finished == NSNumber(value: FBFileReaderState.finishedReadingNormally.rawValue))
  }

  @Test
  func invalidationWaitsForInFlightReadToFinish() async throws {
    sReceiveGate = DispatchSemaphore(value: 0)
    var calls = CreateZeroedAMDCalls()
    calls.ServiceConnectionGetSecureIOContext = { _ in nil }
    calls.ServiceConnectionReceive = blockingReceive
    calls.ServiceConnectionInvalidate = invalidateUnblockingReceive
    // The reference is held here so the retain below lands on the same instance the connection
    // stores: invalidate releases it, standing in for the +1 MobileDevice hands over.
    let connectionRef = "fake-connection-ref" as AnyObject
    let connection = makeConnection(calls: calls, connection: connectionRef)
    _ = Unmanaged.passRetained(connectionRef)
    let consumer = FBDataBuffer.accumulatingBuffer()
    let queue = DispatchQueue(label: "com.facebook.fbdevicecontrol.tests.blocked-reader")
    let reader = connection.readFromConnectionWriting(to: consumer, on: queue)

    _ = try await bridgeFBFuture(reader.startReading())

    // Invalidation unblocks the (gated) receive and must not return until the read loop has
    // exited.
    try connection.invalidate()
    #expect(reader.finishedReading.state == .done)
  }

  @Test
  func invalidationLeaksTheConnectionWhenTheReadDoesNotFinish() async throws {
    sReceiveGate = DispatchSemaphore(value: 0)
    var calls = CreateZeroedAMDCalls()
    calls.ServiceConnectionGetSecureIOContext = { _ in nil }
    calls.ServiceConnectionReceive = blockingReceive
    calls.ServiceConnectionInvalidate = invalidateLeavingReceiveBlocked
    weak var leaked: ConnectionReference?
    let reader: any FileReaderProtocol
    do {
      let connectionRef = ConnectionReference()
      leaked = connectionRef
      let connection = makeConnection(calls: calls, connection: connectionRef)
      connection.readerDrainTimeout = 0.1
      _ = Unmanaged.passRetained(connectionRef)
      let queue = DispatchQueue(label: "com.facebook.fbdevicecontrol.tests.stuck-reader")
      reader = connection.readFromConnectionWriting(to: FBDataBuffer.accumulatingBuffer(), on: queue)
      _ = try await bridgeFBFuture(reader.startReading())

      try connection.invalidate()
    }

    // The blocked read holds the reference while it is inside receive, so whether invalidate
    // released it is only observable once the read has returned.
    sReceiveGate.signal()
    _ = try await bridgeFBFuture(reader.finishedReading)
    #expect(leaked != nil, "a connection whose read did not drain must be leaked rather than released")
    if let leaked {
      Unmanaged.passUnretained(leaked).release()
    }
  }
}
