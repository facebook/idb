/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionDiscovery
import CompanionServer
import Darwin
import Foundation
import Testing

/// Exercises the companion server end to end over a real Unix domain socket:
/// binding, registering in the v2 registry, accepting connections, receiving a
/// JSON-RPC request, and tearing down on close.
@Suite
struct CompanionServerTests {
  @Test
  func bindsRegistersAcceptsAndCloses() async throws {
    try await withTemporaryRegistry { registry in
      let udid = uniqueUDID()
      let expectedPath = CompanionPaths(version: .v2).companionSocketPath(forUDID: udid)
      let server = CompanionServer(udid: udid, version: .v2, registry: registry)
      defer { unlink(expectedPath) }

      let info = try await server.start()
      #expect(info.udid == udid)
      #expect(info.address == .domainSocket(path: expectedPath))
      #expect(info.pid == ProcessInfo.processInfo.processIdentifier)

      // It registered itself in the v2 registry...
      #expect(try registry.companions().map(\.udid) == [udid])
      // ...and is actually listening (the discovery liveness probe connects).
      #expect(CompanionConnectivity.isDomainSocketBound(path: expectedPath))

      try await server.close()

      // Closing deregisters and removes the socket, so it is no longer reachable.
      #expect(try registry.companions().isEmpty)
      #expect(!CompanionConnectivity.isDomainSocketBound(path: expectedPath))
    }
  }

  @Test
  func receivesSentJSONRPCRequest() async throws {
    try await withTemporaryRegistry { registry in
      let recorder = RequestRecorder()
      let udid = uniqueUDID()
      let expectedPath = CompanionPaths(version: .v2).companionSocketPath(forUDID: udid)
      let server = CompanionServer(udid: udid, version: .v2, registry: registry, onRequest: { recorder.record($0) })
      defer { unlink(expectedPath) }

      _ = try await server.start()

      let fd = connect(toSocketPath: expectedPath)
      defer { close(fd) }
      writeLine(#"{"jsonrpc":"2.0","method":"ping","params":{"x":1},"id":7}"#, to: fd)

      try await waitUntil { recorder.count == 1 }

      let received = recorder.requests.first
      #expect(received?.method == "ping")
      #expect(received?.jsonrpc == "2.0")
      #expect(received?.id == .number(7))
      #expect(received?.params == .object(["x": .number(1)]))

      try await server.close()
    }
  }

  // MARK: - Idle shutdown

  @Test
  func shutsDownWhenIdle() async throws {
    try await withTemporaryRegistry { registry in
      let udid = uniqueUDID()
      let path = CompanionPaths(version: .v2).companionSocketPath(forUDID: udid)
      let server = CompanionServer(udid: udid, version: .v2, idleShutdownTime: 0.3, registry: registry)
      defer { unlink(path) }

      _ = try await server.start()
      #expect(CompanionConnectivity.isDomainSocketBound(path: path))

      // With no requests, the server closes itself, so the socket stops accepting.
      // (Probing with isDomainSocketBound connects without sending, which is not
      // counted as activity, so it does not keep resetting the idle timer.)
      try await waitUntil { !CompanionConnectivity.isDomainSocketBound(path: path) }
      #expect(!CompanionConnectivity.isDomainSocketBound(path: path))

      try await server.close()
    }
  }

  @Test
  func activityResetsIdleTimer() async throws {
    try await withTemporaryRegistry { registry in
      let udid = uniqueUDID()
      let path = CompanionPaths(version: .v2).companionSocketPath(forUDID: udid)
      // Generous window so wall-clock jitter on a loaded machine can't fire it
      // early: requests arrive every ~0.2s, far inside the 2s window.
      let server = CompanionServer(udid: udid, version: .v2, idleShutdownTime: 2.0, registry: registry)
      defer { unlink(path) }

      _ = try await server.start()

      // Send a request every ~0.2s for ~1s; each one resets the timer, so the
      // server must still be up afterwards.
      for _ in 0..<5 {
        sendActivity(toSocketPath: path)
        try await Task.sleep(nanoseconds: 200_000_000)
      }
      #expect(CompanionConnectivity.isDomainSocketBound(path: path))

      // Once it goes quiet, it shuts down.
      try await waitUntil(timeout: 8) { !CompanionConnectivity.isDomainSocketBound(path: path) }
      #expect(!CompanionConnectivity.isDomainSocketBound(path: path))

      try await server.close()
    }
  }

  @Test
  func idleTimerPausedWhileProcessing() async throws {
    try await withTemporaryRegistry { registry in
      let udid = uniqueUDID()
      let path = CompanionPaths(version: .v2).companionSocketPath(forUDID: udid)
      // The handler sleeps far longer than the idle timeout, so the timer must be
      // paused for the whole time the request is in flight, then restart after.
      let server = CompanionServer(
        udid: udid, version: .v2, idleShutdownTime: 0.5, registry: registry,
        onRequest: { _ in try? await Task.sleep(nanoseconds: 2_000_000_000) })
      defer { unlink(path) }

      _ = try await server.start()

      // Fire-and-forget a request (connection closed immediately, as idb-forward
      // does), then confirm the server is still up at 1s — well past the 0.5s
      // idle timeout — because the in-flight request paused the timer.
      sendActivity(toSocketPath: path)
      try await Task.sleep(nanoseconds: 1_000_000_000)
      #expect(CompanionConnectivity.isDomainSocketBound(path: path))

      // After the request finishes (~2s) the timer restarts and it shuts down.
      try await waitUntil(timeout: 6) { !CompanionConnectivity.isDomainSocketBound(path: path) }
      #expect(!CompanionConnectivity.isDomainSocketBound(path: path))

      try await server.close()
    }
  }

  // MARK: - Helpers

  private func uniqueUDID() -> String {
    "TEST-\(UUID().uuidString)"
  }

  /// Runs `body` with a registry backed by an isolated temporary state file, so
  /// nothing touches the real `/tmp/idb2/state`.
  private func withTemporaryRegistry(_ body: (CompanionRegistry) async throws -> Void) async throws {
    let directory = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("companion_server_tests_\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let statePath = (directory as NSString).appendingPathComponent("state")
    try await body(CompanionRegistry(stateFilePath: statePath))
  }

  /// Polls `condition` until it holds or `timeout` elapses.
  private func waitUntil(timeout: TimeInterval = 5, _ condition: @Sendable () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
      if Date() >= deadline {
        return
      }
      try await Task.sleep(nanoseconds: 20_000_000) // 20ms
    }
  }

  /// Connects a client socket to `path`, returning the connected fd. Crashes on
  /// failure (a test setup error).
  private func connect(toSocketPath path: String) -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    precondition(fd >= 0, "socket() failed (errno \(errno))")
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    precondition(path.utf8.count < capacity, "socket path too long for sun_path")
    withUnsafeMutablePointer(to: &addr.sun_path) { rawPointer in
      rawPointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
        _ = strncpy(destination, path, capacity - 1)
      }
    }
    let length = socklen_t(MemoryLayout<sockaddr_un>.size)
    let result = withUnsafePointer(to: &addr) { addrPointer in
      addrPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        Darwin.connect(fd, sockaddrPointer, length)
      }
    }
    precondition(result == 0, "connect() failed (errno \(errno))")
    return fd
  }

  /// Writes `line` followed by a newline to `fd`.
  private func writeLine(_ line: String, to fd: Int32) {
    var bytes = Array(line.utf8)
    bytes.append(UInt8(ascii: "\n"))
    bytes.withUnsafeBytes { raw in
      _ = Darwin.write(fd, raw.baseAddress, raw.count)
    }
  }

  /// Best-effort: sends one JSON-RPC line to the server to count as activity,
  /// ignoring any failure (so a slow/closed socket can't crash the test).
  private func sendActivity(toSocketPath path: String) {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return }
    defer { close(fd) }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    guard path.utf8.count < capacity else { return }
    withUnsafeMutablePointer(to: &addr.sun_path) { rawPointer in
      rawPointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
        _ = strncpy(destination, path, capacity - 1)
      }
    }
    let length = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &addr) { addrPointer in
      addrPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        Darwin.connect(fd, sockaddrPointer, length)
      }
    }
    guard connected == 0 else { return }
    writeLine(#"{"jsonrpc":"2.0","method":"ping"}"#, to: fd)
    // Keep the connection open and read until the server closes it (its receipt
    // ack), so the request is reliably delivered.
    var byte: UInt8 = 0
    while Darwin.read(fd, &byte, 1) > 0 {}
  }
}

/// Thread-safe collector for the requests the server hands to its handler (which
/// is invoked on a NIO event-loop thread).
private final class RequestRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [JSONRPCRequest] = []

  func record(_ request: JSONRPCRequest) {
    lock.lock()
    defer { lock.unlock() }
    storage.append(request)
  }

  var requests: [JSONRPCRequest] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return storage.count
  }
}
