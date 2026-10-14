/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorCodeInjection
import Foundation
import Testing

@Suite
struct ControlSocketClientTests {

  @Test
  func readsTheShimsGreeting() async throws {
    let shim = try FakeReplShim()
    async let client = ControlSocketClient.connect(path: shim.path, timeout: 5)
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
    async let client = ControlSocketClient.connect(path: shim.path, timeout: 5)
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
    async let client = ControlSocketClient.connect(path: shim.path, timeout: 5)
    let connection = try await shim.accept()
    try connection.send(["type": "result"])
    let connected = try await client

    await #expect(throws: CodeInjectionError.missingGreeting(received: "result")) { try await connected.readGreeting() }
  }

  @Test
  func executeSendsTheDylibAndSymbolAndReturnsTheResult() async throws {
    let shim = try FakeReplShim()
    let client = try await connectedClient(to: shim)
    let connection = shim.connection!

    async let result = client.run(dylibPath: "/tmp/run.dylib", symbol: "idb_repl_3") { _ in .success(Data()) }
    let request = try await connection.receive()
    #expect(request["type"] as? String == "execute")
    #expect(request["dylib"] as? String == "/tmp/run.dylib")
    #expect(request["symbol"] as? String == "idb_repl_3")
    try connection.send(["type": "result", "success": true, "result": "42", "nextRunIndex": 4])

    let (outcome, nextRunIndex) = try await result
    #expect(try outcome.get() == "42")
    #expect(nextRunIndex == 4)
  }

  @Test
  func aFailedExecuteReportsTheShimsError() async throws {
    let shim = try FakeReplShim()
    let client = try await connectedClient(to: shim)
    let connection = shim.connection!

    async let result = client.run(dylibPath: "/tmp/run.dylib", symbol: "idb_repl_0") { _ in .success(Data()) }
    _ = try await connection.receive()
    try connection.send(["type": "result", "success": false, "error": "dlopen failed"])

    let (outcome, _) = try await result
    guard case let .failure(failure) = outcome else {
      Issue.record("Expected the shim's error, got \(outcome)")
      return
    }
    #expect(failure.message == "dlopen failed")
  }

  @Test
  func aHostCommandIsAnsweredBeforeTheResult() async throws {
    let shim = try FakeReplShim()
    let client = try await connectedClient(to: shim)
    let connection = shim.connection!
    let command = Data("tap".utf8)
    let reply = Data("tapped".utf8)

    async let result = client.run(dylibPath: "/tmp/run.dylib", symbol: "idb_repl_0") { received in
      received == command ? .success(reply) : .failure(HostCommandFailure("unexpected command"))
    }
    _ = try await connection.receive()
    try connection.send(["type": "host_command", "command": command])
    let hostResult = try await connection.receive()
    #expect(hostResult["type"] as? String == "host_result")
    #expect(hostResult["success"] as? Bool == true)
    #expect(hostResult["result"] as? Data == reply)
    try connection.send(["type": "result", "success": true, "result": ""])

    #expect(try await result.outcome.get() == "")
  }

  @Test
  func aFailedHostCommandIsAnsweredWithItsError() async throws {
    let shim = try FakeReplShim()
    let client = try await connectedClient(to: shim)
    let connection = shim.connection!

    async let result = client.run(dylibPath: "/tmp/run.dylib", symbol: "idb_repl_0") { _ in
      .failure(HostCommandFailure("no such element"))
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

    let result = Task { try await client.run(dylibPath: "/tmp/run.dylib", symbol: "idb_repl_0") { _ in .success(Data()) } }
    _ = try await connection.receive()
    connection.close()

    await #expect(throws: CodeInjectionError.disconnected) { try await result.value }
  }

  @Test
  func connectingToASocketNobodyServesTimesOut() async throws {
    let path = FakeReplShim.temporarySocketPath()
    await #expect(throws: CodeInjectionError.connectTimedOut(path: path)) { try await ControlSocketClient.connect(path: path, timeout: 0.2) }
  }

  @Test
  func aSocketPathLongerThanSunPathIsRefused() async throws {
    let path = "/tmp/" + String(repeating: "x", count: 200) + ".sock"
    await #expect(throws: CodeInjectionError.socketPathTooLong(path: path)) { try await ControlSocketClient.connect(path: path, timeout: 5) }
  }

  private func connectedClient(to shim: FakeReplShim) async throws -> ControlSocketClient {
    async let client = ControlSocketClient.connect(path: shim.path, timeout: 5)
    let connection = try await shim.accept()
    try connection.send(["type": "greeting"])
    let connected = try await client
    _ = try await connected.readGreeting()
    return connected
  }
}

private struct HostCommandFailure: Error, CustomStringConvertible {
  let description: String

  init(_ description: String) {
    self.description = description
  }
}
