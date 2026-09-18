/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import Testing

/// Records the clients handed to it, so a test can observe an accepted connection. The file
/// descriptors are owned by the delegate once delivered — nothing else closes them.
private final class RecordingSocketServerDelegate: NSObject, SocketServerDelegate {

  let queue = DispatchQueue(label: "com.facebook.fbcontrolcore.tests.socketserver")

  private let lock = NSLock()
  private var connected: [Int32] = []

  var fileDescriptors: [Int32] {
    lock.lock()
    defer { lock.unlock() }
    return connected
  }

  func socketServer(_ server: FBSocketServer, clientConnected address: in6_addr, fileDescriptor: Int32) {
    lock.lock()
    connected.append(fileDescriptor)
    lock.unlock()
  }

  func closeAll() {
    for fileDescriptor in fileDescriptors {
      close(fileDescriptor)
    }
  }
}

/// Pins what the socket server does with a port and with its own lifecycle: the ephemeral port it
/// reads back from the kernel, the two failures it reports for a lifecycle called out of order, and
/// the delegate callback an accepted client produces.
@Suite("Socket server")
struct FBSocketServerTests {

  /// Port zero asks the kernel for an ephemeral port, so nothing here collides with a port another
  /// test or another process has already bound.
  private static let ephemeralPort: in_port_t = 0

  private static func connect(toPort port: in_port_t) throws -> Int32 {
    let client = socket(AF_INET6, SOCK_STREAM, 0)
    try #require(client > 0)
    var address = sockaddr_in6()
    address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
    address.sin6_family = sa_family_t(AF_INET6)
    address.sin6_port = port.bigEndian
    address.sin6_addr = in6addr_loopback
    let result = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddress in
        Darwin.connect(client, sockaddress, socklen_t(MemoryLayout<sockaddr_in6>.size))
      }
    }
    try #require(result == 0, "Failed to connect to the server on port \(port)")
    return client
  }

  private static func waitFor(
    _ description: String,
    timeout: TimeInterval = 5,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
  ) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline, !condition() {
      usleep(20_000)
    }
    if !condition() {
      Issue.record("Timed out after \(timeout)s waiting for \(description)", sourceLocation: sourceLocation)
    }
  }

  @Test("Listening on port zero reads back the port the kernel bound")
  func listeningOnPortZeroReadsBackTheBoundPort() throws {
    let delegate = RecordingSocketServerDelegate()
    let server = FBSocketServer(onPort: Self.ephemeralPort, delegate: delegate)
    defer { _ = server.stopListening() }

    try server.startListening().`await`()

    #expect(server.port != 0)
  }

  @Test("A server that is already listening refuses to listen again")
  func listeningTwiceFails() throws {
    let delegate = RecordingSocketServerDelegate()
    let server = FBSocketServer(onPort: Self.ephemeralPort, delegate: delegate)
    defer { _ = server.stopListening() }
    try server.startListening().`await`()

    #expect(throws: (any Error).self) {
      try server.startListening().`await`()
    }
  }

  @Test("A server that is not listening refuses to stop")
  func stoppingWithoutListeningFails() throws {
    let delegate = RecordingSocketServerDelegate()
    let server = FBSocketServer(onPort: Self.ephemeralPort, delegate: delegate)

    #expect(throws: (any Error).self) {
      try server.stopListening().`await`()
    }
  }

  @Test("A connected client reaches the delegate with its file descriptor")
  func connectedClientReachesTheDelegate() throws {
    let delegate = RecordingSocketServerDelegate()
    let server = FBSocketServer(onPort: Self.ephemeralPort, delegate: delegate)
    defer {
      _ = server.stopListening()
      delegate.closeAll()
    }
    try server.startListening().`await`()

    let client = try Self.connect(toPort: server.port)
    defer { close(client) }

    Self.waitFor("the delegate to be handed the connected client") { delegate.fileDescriptors.count == 1 }
    #expect(delegate.fileDescriptors.first.map { $0 > 0 } == true)
  }
}
