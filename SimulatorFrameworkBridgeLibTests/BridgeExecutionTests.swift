/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeProtocol
@_implementationOnly import SimulatorFrameworkBridgeSupport
import XCTest

final class BridgeExecutionTests: XCTestCase {
  func testRPCAndSocketAdaptersPreserveTheCommandIdentityAndPartialFailure() throws {
    let commands: [BridgeCommand] = [
      .clearContacts, .clearPhotos, .dns(.list), .proxy(.clear),
      .health(.approve(bundleID: "app", typeIDs: ["step"])),
      .notifications(.delivered(bundleID: "app")), .notifications(.clearDelivered(bundleID: "app")),
      .accessibility(["verb": .string("describe")]), .ping,
    ]
    let expected = BridgeResult(exitCode: 23, values: [.object(["identifier": .string("first")]), .object(["identifier": .string("second")])])
    var received: [BridgeCommand] = []
    for command in commands {
      let request = BridgeRequest(command: command, id: "test")
      let execute: (BridgeCommand) -> BridgeResult = {
        received.append($0)
        return expected
      }
      let cli = BridgeRPC.process(Data(try request.arguments[1].utf8), execute: execute)
      let socket = BridgeRPC.handle(try request.encoded(), execute: execute)
      XCTAssertEqual(cli.data, socket.data)
      XCTAssertEqual(try BridgeResponse.decode(cli.data, for: request).result, expected)
      XCTAssertEqual(cli.exitCode, 23)
      XCTAssertFalse(cli.shutdown)
      XCTAssertFalse(socket.shutdown)
    }
    XCTAssertEqual(received, commands.flatMap { [$0, $0] })
  }

  func testInvalidRequestsNeverExecuteAndDoNotPoisonTheNextRequest() throws {
    var calls = 0
    let execute: (BridgeCommand) -> BridgeResult = { _ in
      calls += 1
      return BridgeResult(exitCode: 0)
    }
    for text in ["{", "null"] {
      let reply = BridgeRPC.process(Data(text.utf8), execute: execute)
      XCTAssertEqual(reply.exitCode, 1)
      XCTAssertFalse(reply.shutdown)
      let response = try JSONDecoder().decode(BridgeResponse.self, from: reply.data)
      XCTAssertNil(response.id)
      XCTAssertEqual(response.result.exitCode, 1)
      XCTAssertNotNil(failureMessage(response.result))
    }
    // A request whose identity survives decoding is answered under that identity, so the host can
    // match the failure to what it sent instead of reporting a mismatched response.
    let unanswerable: [(String, String)] = [
      (#"{"version":2,"id":"future-version","command":{"ping":{}}}"#, "unsupportedVersion(2)"),
      (#"{"version":1,"id":"future-command","command":{"future":{}}}"#, "command"),
    ]
    for (text, expected) in unanswerable {
      let reply = BridgeRPC.process(Data(text.utf8), execute: execute)
      XCTAssertEqual(reply.exitCode, 1)
      let request = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
      let response = try JSONDecoder().decode(BridgeResponse.self, from: reply.data)
      XCTAssertEqual(response.id, request["id"] as? String)
      XCTAssertEqual(response.result.exitCode, 1)
      let message = try XCTUnwrap(failureMessage(response.result))
      XCTAssertTrue(message.contains(expected), message)
    }
    XCTAssertEqual(calls, 0)
    let request = BridgeRequest(command: .ping)
    XCTAssertEqual(try BridgeResponse.decode(BridgeRPC.process(request.encoded(), execute: execute).data, for: request).result.exitCode, 0)
    XCTAssertEqual(calls, 1)
  }

  func testOversizedAndInvalidOutputBecomesAMatchingFailureInBothAdapters() throws {
    let request = BridgeRequest(command: .dns(.list), id: "bounded")
    for value in [BridgeJSONValue.string(String(repeating: "x", count: BridgeFrame.maximumSize)), .number(.infinity)] {
      let execute: (BridgeCommand) -> BridgeResult = { _ in BridgeResult(exitCode: 0, values: [value]) }
      let cli = BridgeRPC.process(try request.encoded(), execute: execute)
      let socket = BridgeRPC.handle(try request.encoded(), execute: execute)
      XCTAssertEqual(cli.data, socket.data)
      XCTAssertEqual(cli.exitCode, 1)
      XCTAssertLessThan(cli.data.count, BridgeFrame.maximumSize)
      XCTAssertEqual(try BridgeResponse.decode(cli.data, for: request).result.exitCode, 1)
    }
  }

  private func failureMessage(_ result: BridgeResult) -> String? {
    guard result.values.count == 1, case let .object(fields) = result.values[0], case let .string(message)? = fields["error"] else { return nil }
    return message
  }

  func testServeBindsTheAccessibilityRuntimeBeforeItsFirstClient() throws {
    let path = "/tmp/sfb-prepare-" + UUID().uuidString
    defer { unlink(path) }
    let probe = FBAXBridgeServeProbe(["SimulatorFrameworkBridge", "serve", path, "--startup-timeout", "1"])
    XCTAssertEqual(probe["status"] as? Int32, 0)
    XCTAssertEqual(probe["calls"] as? Int, 1, "the runtime is bound once, before any client connects")
  }

  func testOnlySuccessfulShutdownEndsTheServer() throws {
    for command: BridgeCommand in [.ping, .shutdown] {
      for status: Int32 in [0, 1] {
        let request = BridgeRequest(command: command)
        let response = BridgeRPC.process(try request.encoded()) { _ in BridgeResult(exitCode: status) }
        XCTAssertEqual(response.shutdown, command == .shutdown && status == 0)
      }
    }
  }

  func testOutputIsRequestLocalRetainsOrderAndReportsEncodingFailures() {
    let first = BridgeOutput()
    XCTAssertTrue(first.write(["id": "first"]))
    XCTAssertFalse(first.write(["date": Double.infinity]))
    XCTAssertTrue(first.write(["id": "second"]))
    XCTAssertEqual(first.finish(status: 0), BridgeResult(exitCode: 1, values: [.object(["id": .string("first")]), .object(["id": .string("second")])]))
    XCTAssertEqual(BridgeOutput().finish(status: 0), BridgeResult(exitCode: 0))
  }

  func testNetworkCommandsCollectResultsWithoutWritingStdout() throws {
    let runtime = FBNetworkConfigurationTestRuntime()
    runtime.install()
    defer { runtime.uninstall() }
    runtime.configuration = ["ServerAddresses": ["::1", "1.1.1.1"]]
    var result = BridgeResult(exitCode: 1)
    let printed = FBStdoutWhileRunning { result = BridgeServices.execute(.dns(.list)) }
    XCTAssertEqual(printed, "")
    XCTAssertEqual(result, BridgeResult(exitCode: 0, values: [.object(["ServerAddresses": .array([.string("::1"), .string("1.1.1.1")])])]))
    XCTAssertEqual(BridgeServices.execute(.dns(.set(servers: ["8.8.8.8"]))).exitCode, 0)
    XCTAssertEqual(runtime.writes as NSArray, [["ServerAddresses": ["8.8.8.8"]]] as NSArray)
    XCTAssertEqual(Array(runtime.operations.suffix(2)) as NSArray, ["write", "notify"] as NSArray)
    runtime.configuration = ["unsupported": Date()]
    XCTAssertEqual(BridgeServices.execute(.dns(.list)).exitCode, 1)
    runtime.configuration = ["SOCKSProxy": "localhost"]
    XCTAssertEqual(BridgeServices.execute(.proxy(.list)), BridgeResult(exitCode: 0, values: [.object(["SOCKSProxy": .string("localhost")])]))
    XCTAssertEqual(BridgeServices.execute(.proxy(.set(host: "::1", port: 1080, kind: .socks))).exitCode, 0)
    XCTAssertEqual((runtime.writes.lastObject as? [String: Any])?["SOCKSPort"] as? Int, 1080)
  }

  // An unset proto3 string arrives empty, and answering 0 would report a malformed request as done.
  func testDeliveredNotificationCommandsRefuseAnEmptyBundleIDBeforeReachingTheDaemon() {
    XCTAssertEqual(BridgeServices.execute(.notifications(.delivered(bundleID: ""))).exitCode, 1)
    XCTAssertEqual(BridgeServices.execute(.notifications(.clearDelivered(bundleID: ""))).exitCode, 1)
  }

  func testTypedHealthTimeoutsReportFailureWithoutMutatingTheNextResult() throws {
    for stage in ["seed", "set", "clear", "list"] {
      let runtime = FBHealthTestRuntime()
      runtime.typeFactories = ["step": "HKQuantityType"]
      runtime.deferredCompletion = stage
      runtime.install()
      defer { runtime.uninstall() }
      let command: BridgeCommand
      switch stage {
      case "clear": command = .health(.clear(bundleID: "app"))
      case "list": command = .health(.list(bundleID: "app"))
      default: command = .health(.approve(bundleID: "app", typeIDs: ["step"]))
      }
      let result = BridgeServices.execute(command)
      XCTAssertEqual(result.exitCode, 1, stage)
      guard case let .object(value)? = result.values.first else { return XCTFail("missing timeout response") }
      XCTAssertEqual(value["completionStatus"], .string("timedOut"))
      XCTAssertEqual(value["ok"], .bool(false))
      runtime.completePendingCallbacks()
      XCTAssertEqual(result.values.first, .object(value))
      runtime.deferredCompletion = ""
      XCTAssertEqual(BridgeServices.execute(command).exitCode, 0)
    }
  }
}
