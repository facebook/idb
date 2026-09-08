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

private let debugServerService = "com.apple.debugserver"

/// Everything the debug server asks of the AMDevice. The session is released once the service has
/// started, so it is closed while the connection the server proxies is still open.
private let debugServerSessionEvents = [
  "connect",
  "is_paired",
  "validate_pairing",
  "start_session",
  "secure_start_service:\(debugServerService)",
  "stop_session",
  "disconnect",
]

/// `FBIDBCommandExecutor` holds the server across separate `debugserver_start`, `debugserver_status`
/// and `debugserver_stop` requests, so the service connection outlives the call that opened it.
///
/// Pinned on the main actor: the fake records its calls from the device's work and async queues,
/// both of which are the main queue, so the assertions have to read them from the same one.
@MainActor
@Suite(.serialized)
final class FBDeviceDebugServerTests {

  private let amDevice = FakeAMDevice()

  private var debugService: FakeLockdownService {
    amDevice.service(debugServerService)
  }

  /// Teardown is enqueued on the queue the server was built with when its completion resolves, so
  /// it can still be pending when the await that triggered it resumes.
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

  /// Port zero asks the kernel for an ephemeral one, so nothing here collides with a port another
  /// test or another process is already bound to. Nothing connects over TCP either — the one test
  /// that needs a client reaches the delegate callback directly.
  private func makeDebugServer() async throws -> FBDeviceDebugServer {
    let device = amDevice.makeAMDevice()
    return try await bridgeFBFuture(
      FBDeviceDebugServer.debugServer(
        forServiceConnection: device.startService(debugServerService),
        port: 0,
        lldbBootstrapCommands: ["platform select remote-ios"],
        queue: DispatchQueue.main,
        logger: FBControlCoreGlobalConfiguration.defaultLogger))
  }

  /// The server holds the service connection open, with the AMDevice session that started the
  /// service already closed.
  @Test
  func debugServer_HoldsTheServiceConnectionOpenWhileItIsRunning() async throws {
    let server = try await makeDebugServer()

    await waitFor("the AMDevice session to close") { self.amDevice.events == debugServerSessionEvents }
    #expect((debugServerSessionEvents) == (amDevice.events))
    #expect(!debugService.isInvalidated)
    #expect((server.lldbBootstrapCommands) == (["platform select remote-ios"]))
  }

  @Test
  func debugServer_InvalidatesTheServiceConnectionWhenCancelled() async throws {
    let server = try await makeDebugServer()
    await waitFor("the AMDevice session to close") { self.amDevice.events == debugServerSessionEvents }
    #expect(!debugService.isInvalidated)

    try await server.cancel()

    await waitFor("the service connection to be invalidated") { self.debugService.isInvalidated }
    // Invalidation is all that is left to do: the session was released when the service started.
    #expect((debugServerSessionEvents) == (amDevice.events))
  }

  /// The client disconnecting invalidates the service connection without anyone calling `cancel()`.
  ///
  /// A socket pair stands in for an accepted client, handed straight to the delegate callback. The
  /// server binds an ephemeral port that a test has no way to learn, and the callback ignores which
  /// socket server it is told about, so the one passed here is a placeholder.
  @Test
  func debugServer_InvalidatesTheServiceConnectionWhenTheClientDisconnects() async throws {
    let server = try await makeDebugServer()
    await waitFor("the AMDevice session to close") { self.amDevice.events == debugServerSessionEvents }
    #expect(!debugService.isInvalidated)

    var sockets: [Int32] = [-1, -1]
    #expect((socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets)) == (0))
    server.socketServer(
      FBSocketServer(onPort: 0, delegate: server),
      clientConnected: in6addr_any,
      fileDescriptor: sockets[0])
    // The device has nothing to relay, so the connection-side loop ends on its first read; hanging
    // up the client end is what ends the other one.
    close(sockets[1])

    await waitFor("the service connection to be invalidated") { self.debugService.isInvalidated }
    #expect((debugServerSessionEvents) == (amDevice.events))
  }
}
