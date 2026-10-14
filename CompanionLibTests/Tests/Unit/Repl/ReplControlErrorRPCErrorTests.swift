/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import FBSimulatorCodeInjection
import Foundation
import GRPCCore
import Testing

/// The status and message the `repl` method ends with when its session fails: the control socket's
/// failures by kind, and a host that could not be started as an internal error carrying its reason.
@Suite
struct ReplControlErrorRPCErrorTests {

  @Test(arguments: [
    (ReplControlError.socketPathTooLong(path: "/tmp/x.sock"), RPCError.Code.invalidArgument, "repl: socket path too long (11 bytes): /tmp/x.sock"),
    (.connectTimedOut(path: "/tmp/x.sock"), .deadlineExceeded, "repl: timed out connecting to control socket at /tmp/x.sock"),
    (.disconnected, .unavailable, "repl: control socket closed before a complete message was received (the test process may have crashed)"),
    (.socketCreationFailed, .internalError, "repl: failed to create socket"),
    (.missingGreeting(received: "result"), .internalError, "repl: expected a 'greeting' message, got type 'result'"),
    (.unexpectedMessage(received: nil), .internalError, "repl: unexpected control-socket message type 'nil'"),
    (.invalidMessage, .internalError, "repl: invalid control-socket message"),
    (.readFailed(errno: ECONNRESET), .internalError, "repl: failed to read from control socket: Connection reset by peer"),
    (.writeFailed, .internalError, "repl: failed to write to control socket"),
    (.hostCommandDidNotComplete, .internalError, "repl: host command did not complete"),
  ])
  func aControlSocketFailureEndsTheReplWithItsStatus(_ error: ReplControlError, _ code: RPCError.Code, _ message: String) async {
    let rpcError = await endingTheRepl(with: error)
    #expect(rpcError.code == code)
    #expect(rpcError.message == message)
  }

  @Test(arguments: [
    (SimulatorReplError.bundledResourceMissing(item: "libRepl-iOS.dylib"), "libRepl-iOS.dylib not found in the bundled resources"),
    (.socketDirectoryCreationFailed(path: "/tmp/idb_repl_501"), "Could not create a private REPL socket directory at /tmp/idb_repl_501"),
    (
      .targetIsNotALaunchableApp(bundleID: "com.apple.springboard", processIdentifier: 42),
      "com.apple.springboard is managed by launchd (pid 42), not launched as an app, so launching it returns the process already running and the REPL dylib is never injected. Target an app bundle instead."
    ),
  ])
  func aHostThatCannotStartEndsTheReplAsAnInternalError(_ error: SimulatorReplError, _ message: String) async {
    let rpcError = await endingTheRepl(with: error)
    #expect(rpcError.code == .internalError)
    #expect(rpcError.message == message)
  }

  /// What the server reports when the `repl` method throws `error` while setting up or running its
  /// session.
  private func endingTheRepl(with error: any Error) async -> RPCError {
    do {
      try await reportingReplControlErrors { throw error }
      Issue.record("Expected \(error) to end the repl")
      return RPCError(code: .unknown, message: "")
    } catch {
      return ErrorMapping.rpcError(from: error)
    }
  }
}
