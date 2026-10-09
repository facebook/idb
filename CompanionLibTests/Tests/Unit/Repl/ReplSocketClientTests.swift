/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import Foundation
import Testing

@Suite
struct ReplSocketClientTests {

  @Test
  func readsTheShimsGreeting() async throws {
    let shim = try FakeReplShim()
    async let client = ReplSocketClient.connect(path: shim.path, timeout: 5)
    let connection = try await shim.accept()
    try connection.send(["type": "greeting", "interfaces": ["/tmp/A.swiftinterface"], "nextRunIndex": 7, "sessionID": "session"])

    let greeting = try await client.readGreeting()
    #expect(greeting.interfaces == ["/tmp/A.swiftinterface"])
    #expect(greeting.nextRunIndex == 7)
    #expect(greeting.sessionID == "session")
  }

  @Test
  func aGreetingWithoutOptionalFieldsDefaultsThem() async throws {
    let shim = try FakeReplShim()
    async let client = ReplSocketClient.connect(path: shim.path, timeout: 5)
    let connection = try await shim.accept()
    try connection.send(["type": "greeting"])

    let greeting = try await client.readGreeting()
    #expect(greeting.interfaces.isEmpty)
    #expect(greeting.nextRunIndex == 0)
    #expect(greeting.sessionID == "")
  }

  @Test
  func aFirstMessageThatIsNotAGreetingFails() async throws {
    let shim = try FakeReplShim()
    async let client = ReplSocketClient.connect(path: shim.path, timeout: 5)
    let connection = try await shim.accept()
    try connection.send(["type": "result"])
    let connected = try await client

    await #expect(throws: (any Error).self) { try await connected.readGreeting() }
  }

  @Test
  func executeSendsTheDylibAndSymbolAndReturnsTheResult() async throws {
    let shim = try FakeReplShim()
    let client = try await connectedClient(to: shim)
    let connection = shim.connection!

    async let result = client.execute(dylibPath: "/tmp/run.dylib", symbol: "idb_repl_3") { _ in .success(Data()) }
    let request = try await connection.receive()
    #expect(request["type"] as? String == "execute")
    #expect(request["dylib"] as? String == "/tmp/run.dylib")
    #expect(request["symbol"] as? String == "idb_repl_3")
    try connection.send(["type": "result", "success": true, "result": "42", "nextRunIndex": 4])

    let outcome = try await result
    #expect(outcome.success)
    #expect(outcome.output == "42")
    #expect(outcome.nextRunIndex == 4)
  }

  @Test
  func aFailedExecuteReportsTheShimsError() async throws {
    let shim = try FakeReplShim()
    let client = try await connectedClient(to: shim)
    let connection = shim.connection!

    async let result = client.execute(dylibPath: "/tmp/run.dylib", symbol: "idb_repl_0") { _ in .success(Data()) }
    _ = try await connection.receive()
    try connection.send(["type": "result", "success": false, "error": "dlopen failed"])

    let outcome = try await result
    #expect(!outcome.success)
    #expect(outcome.output == "Error: dlopen failed")
  }

  @Test
  func aHostCommandIsAnsweredBeforeTheResult() async throws {
    let shim = try FakeReplShim()
    let client = try await connectedClient(to: shim)
    let connection = shim.connection!
    let command = Data("tap".utf8)
    let reply = Data("tapped".utf8)

    async let result = client.execute(dylibPath: "/tmp/run.dylib", symbol: "idb_repl_0") { received in
      received == command ? .success(reply) : .failure(HostCommandError.message("unexpected command"))
    }
    _ = try await connection.receive()
    try connection.send(["type": "host_command", "command": command])
    let hostResult = try await connection.receive()
    #expect(hostResult["type"] as? String == "host_result")
    #expect(hostResult["success"] as? Bool == true)
    #expect(hostResult["result"] as? Data == reply)
    try connection.send(["type": "result", "success": true, "result": ""])

    #expect(try await result.success)
  }

  @Test
  func aFailedHostCommandIsAnsweredWithItsError() async throws {
    let shim = try FakeReplShim()
    let client = try await connectedClient(to: shim)
    let connection = shim.connection!

    async let result = client.execute(dylibPath: "/tmp/run.dylib", symbol: "idb_repl_0") { _ in
      .failure(HostCommandError.message("no such element"))
    }
    _ = try await connection.receive()
    try connection.send(["type": "host_command", "command": Data()])
    let hostResult = try await connection.receive()
    #expect(hostResult["success"] as? Bool == false)
    #expect(hostResult["error"] as? String == "no such element")
    try connection.send(["type": "result", "success": true, "result": ""])

    _ = try await result
  }

  @Test
  func theShimClosingMidExecuteFails() async throws {
    let shim = try FakeReplShim()
    let client = try await connectedClient(to: shim)
    let connection = shim.connection!

    let result = Task { try await client.execute(dylibPath: "/tmp/run.dylib", symbol: "idb_repl_0") { _ in .success(Data()) } }
    _ = try await connection.receive()
    connection.close()

    await #expect(throws: (any Error).self) { try await result.value }
  }

  @Test
  func connectingToASocketNobodyServesTimesOut() async throws {
    let path = FakeReplShim.temporarySocketPath()
    await #expect(throws: (any Error).self) { try await ReplSocketClient.connect(path: path, timeout: 0.2) }
  }

  @Test
  func aSocketPathLongerThanSunPathIsRefused() async throws {
    let path = "/tmp/" + String(repeating: "x", count: 200) + ".sock"
    await #expect(throws: (any Error).self) { try await ReplSocketClient.connect(path: path, timeout: 5) }
  }

  private func connectedClient(to shim: FakeReplShim) async throws -> ReplSocketClient {
    async let client = ReplSocketClient.connect(path: shim.path, timeout: 5)
    let connection = try await shim.accept()
    try connection.send(["type": "greeting"])
    let connected = try await client
    _ = try await connected.readGreeting()
    return connected
  }
}

/// The server half of the REPL control socket, as `ReplSocketServer` serves it from inside the
/// injected process: length-prefixed binary property lists over a unix socket.
private final class FakeReplShim: @unchecked Sendable {

  final class Connection: @unchecked Sendable {
    private let fd: Int32
    private let closeLock = NSLock()
    private var isClosed = false

    init(fd: Int32) {
      self.fd = fd
    }

    func send(_ message: [String: Any]) throws {
      let payload = try PropertyListSerialization.data(fromPropertyList: message, format: .binary, options: 0)
      let length = UInt32(payload.count).bigEndian
      var framed = withUnsafeBytes(of: length) { Data($0) }
      framed.append(payload)
      try framed.withUnsafeBytes { raw in
        var written = 0
        while written < raw.count {
          let n = Darwin.write(fd, raw.baseAddress! + written, raw.count - written)
          guard n > 0 else { throw POSIXError(.EPIPE) }
          written += n
        }
      }
    }

    /// Reads off the cooperative pool: the client under test needs a cooperative thread to service
    /// host commands while the shim waits for its answer.
    func receive() async throws -> [String: Any] {
      try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
          continuation.resume(with: Result { try self.receiveBlocking() })
        }
      }
    }

    private func receiveBlocking() throws -> [String: Any] {
      let header = try read(count: 4)
      let length = header.reduce(0) { ($0 << 8) | Int($1) }
      let payload = try read(count: length)
      guard let message = try PropertyListSerialization.propertyList(from: payload, format: nil) as? [String: Any] else {
        throw POSIXError(.EBADMSG)
      }
      return message
    }

    /// Idempotent: closing a descriptor twice could close one another test has since opened.
    func close() {
      closeLock.lock()
      defer { closeLock.unlock() }
      guard !isClosed else { return }
      isClosed = true
      Darwin.close(fd)
    }

    private func read(count: Int) throws -> Data {
      var data = Data(count: count)
      var total = 0
      while total < count {
        let n = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress! + total, count - total) }
        guard n > 0 else { throw POSIXError(.ECONNRESET) }
        total += n
      }
      return data
    }
  }

  let path = FakeReplShim.temporarySocketPath()
  private let listener: Int32
  private(set) var connection: Connection?

  init() throws {
    listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
      path.withCString { src in memcpy(ptr, src, path.utf8.count + 1) }
    }
    let bound = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard bound == 0, Darwin.listen(listener, 1) == 0 else {
      throw POSIXError(.EADDRNOTAVAIL)
    }
  }

  deinit {
    connection?.close()
    Darwin.close(listener)
    Darwin.unlink(path)
  }

  func accept() async throws -> Connection {
    let listener = self.listener
    let fd: Int32 = await withCheckedContinuation { continuation in
      DispatchQueue.global().async { continuation.resume(returning: Darwin.accept(listener, nil, nil)) }
    }
    guard fd >= 0 else { throw POSIXError(.ECONNABORTED) }
    let connection = Connection(fd: fd)
    self.connection = connection
    return connection
  }

  static func temporarySocketPath() -> String {
    "/tmp/idb_repl_test_\(UUID().uuidString.prefix(8)).sock"
  }
}
