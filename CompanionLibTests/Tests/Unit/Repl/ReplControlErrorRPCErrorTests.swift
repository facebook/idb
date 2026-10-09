/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import FBSimulatorCodeInjection
import GRPCCore
import Testing

@Suite
struct ReplControlErrorRPCErrorTests {

  @Test(arguments: [
    (ReplControlError.socketPathTooLong(path: "/tmp/x.sock"), RPCError.Code.invalidArgument),
    (.connectTimedOut(path: "/tmp/x.sock"), .deadlineExceeded),
    (.disconnected, .unavailable),
    (.socketCreationFailed, .internalError),
    (.missingGreeting(received: "result"), .internalError),
    (.unexpectedMessage(received: nil), .internalError),
    (.invalidMessage, .internalError),
    (.writeFailed, .internalError),
  ])
  func aControlSocketFailureEndsTheReplWithItsStatus(_ error: ReplControlError, _ code: RPCError.Code) {
    #expect(error.rpcError.code == code)
    #expect(error.rpcError.message == error.description)
  }

  @Test
  func theMessageIsTheOneClientsAlreadySee() {
    #expect(ReplControlError.connectTimedOut(path: "/tmp/x.sock").rpcError.message == "repl: timed out connecting to control socket at /tmp/x.sock")
    #expect(ReplControlError.missingGreeting(received: "result").rpcError.message == "repl: expected a 'greeting' message, got type 'result'")
  }
}
