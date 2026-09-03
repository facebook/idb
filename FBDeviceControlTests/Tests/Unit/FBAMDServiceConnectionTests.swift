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

/// The connection sends and receives in 4 KiB chunks, so payloads either side of that boundary are
/// what show the loop working.
private let BufferSize = 1024 * 4

private func payload(_ count: Int) -> Data {
  Data((0..<count).map { UInt8($0 % 251) })
}

/// Direct coverage of the raw byte plane of `FBAMDServiceConnection`, which the command-level tests
/// reach only incidentally. The chunking loops, the end-of-file handling and the length header's
/// byte order are the parts a rewrite of this class would most easily get wrong.
@Suite
struct FBAMDServiceConnectionTests {

  // Fresh per test: each test in a Swift Testing suite gets its own suite instance.
  private let amDevice = FakeAMDevice()

  private func makeConnection(named name: String = "com.apple.test") -> (FBAMDServiceConnection, FakeLockdownService) {
    let service = amDevice.service(name)
    let connection = FBAMDServiceConnection(
      name: name,
      connection: service,
      device: amDevice,
      calls: amDevice.calls,
      logger: FBControlCoreGlobalConfiguration.defaultLogger)
    return (connection, service)
  }

  // MARK: - Sending

  @Test
  func sendsAPayloadInBufferSizedChunks() throws {
    let (connection, service) = makeConnection()
    let data = payload(BufferSize * 2 + 100)

    try connection.send(data)

    #expect(service.sendChunks == [BufferSize, BufferSize, 100])
    #expect(service.sentBytes == data)
  }

  @Test
  func sendsASmallPayloadInOneChunk() throws {
    let (connection, service) = makeConnection()

    try connection.send(payload(10))

    #expect(service.sendChunks == [10])
  }

  /// The length header goes out big-endian, unlike everything else written as a raw integer.
  @Test
  func sendWithLengthHeaderPrefixesABigEndianLength() throws {
    let (connection, service) = makeConnection()
    let data = payload(5)

    try connection.send(withLengthHeader: data)

    #expect(service.sentBytes == Data([0x00, 0x00, 0x00, 0x05]) + data)
  }

  @Test
  func reportsASendFailure() throws {
    let (connection, service) = makeConnection()
    service.sendFails = true

    let error = #expect(throws: (any Error).self) {
      try connection.send(payload(10))
    }

    #expect((error as? NSError)?.localizedDescription.hasPrefix("Failure in send of 10 bytes") == true)
  }

  // MARK: - Receiving an exact length

  @Test
  func receivesTheRequestedBytesInBufferSizedChunks() throws {
    let (connection, service) = makeConnection()
    let data = payload(BufferSize * 2 + 100)
    service.readBuffer = data

    let received = try connection.receive(data.count)

    #expect(received == data)
    #expect(service.receiveRequests == [BufferSize, BufferSize, 100])
  }

  /// Running out of bytes part-way is a failure, not a short read — the caller asked for an exact
  /// count.
  @Test
  func failsWhenTheConnectionEndsBeforeTheRequestedLength() throws {
    let (connection, service) = makeConnection()
    service.readBuffer = payload(10)

    let error = #expect(throws: (any Error).self) {
      try connection.receive(20)
    }

    #expect(
      (error as? NSError)?.localizedDescription
        == "Failed to receive 20 bytes, 10 remaining to read and eof reached.")
  }

  @Test
  func reportsAReceiveFailure() throws {
    let (connection, service) = makeConnection()
    service.receiveFails = true

    let error = #expect(throws: (any Error).self) {
      try connection.receive(10)
    }

    #expect((error as? NSError)?.localizedDescription.hasPrefix("Failure in receive of 10 bytes") == true)
  }

  // MARK: - Receiving what is available

  @Test
  func receiveUpToReturnsWhateverIsAvailable() throws {
    let (connection, service) = makeConnection()
    service.readBuffer = payload(3)

    let received = try connection.receiveUp(to: 10)

    #expect(received == payload(3))
  }

  /// Unlike the exact-length receive, reaching the end is an empty result rather than an error.
  @Test
  func receiveUpToReturnsEmptyAtEndOfFile() throws {
    let (connection, _) = makeConnection()

    let received = try connection.receiveUp(to: 10)

    #expect(received == Data())
  }

  // MARK: - Fixed width integers

  @Test
  func roundTripsAnUnsignedInt32InHostOrder() throws {
    let (connection, service) = makeConnection()

    try connection.sendUnsignedInt32(0x1234_5678)
    // Feed what was written back in, so the value read is the value sent rather than one the test
    // planted alongside it.
    service.readBuffer = service.sentBytes
    var received: UInt32 = 0
    try connection.receiveUnsignedInt32(&received)

    #expect(received == 0x1234_5678)
  }

  @Test
  func receivesAnUnsignedInt64InHostOrder() throws {
    let (connection, service) = makeConnection()
    service.readBuffer = withUnsafeBytes(of: UInt64(0x0102_0304_0506_0708)) { Data($0) }

    var received: UInt64 = 0
    try connection.receiveUnsignedInt64(&received)

    #expect(received == 0x0102_0304_0506_0708)
  }

  // MARK: - Lifecycle

  @Test
  func invalidateInvalidatesTheUnderlyingConnection() throws {
    let (connection, service) = makeConnection()
    _ = Unmanaged.passRetained(service)

    try connection.invalidate()

    #expect(service.isInvalidated)
  }

  /// `invalidate` releases the connection itself, because `AMDServiceConnectionInvalidate` does
  /// not. The retain stands in for the one MobileDevice hands over on service start; if the
  /// release stops happening it is that retain which is left behind, so the weak reference is what
  /// detects it. The service is built here rather than through the fake device, which would hold
  /// its own reference and mask the result.
  @Test
  func invalidateReleasesTheConnection() throws {
    weak var released: FakeLockdownService?
    do {
      let service = FakeLockdownService(serviceName: "com.apple.test")
      released = service
      let connection = FBAMDServiceConnection(
        name: service.serviceName,
        connection: service,
        device: amDevice,
        calls: amDevice.calls,
        logger: FBControlCoreGlobalConfiguration.defaultLogger)
      _ = Unmanaged.passRetained(service)
      try connection.invalidate()
      #expect(released != nil, "the local reference is still in scope here")
    }

    #expect(released == nil, "invalidate should have released the retain handed over on service start")
  }

  @Test
  func invalidateFailsOnceTheConnectionIsGone() throws {
    let (connection, service) = makeConnection()
    _ = Unmanaged.passRetained(service)
    try connection.invalidate()

    let error = #expect(throws: (any Error).self) {
      try connection.invalidate()
    }

    #expect((error as? NSError)?.localizedDescription == "No connection to invalidate")
  }
}
