/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeLib
import XCTest

final class ServiceCommandTests: XCTestCase {
  func testIncompleteCommandDoesNotCallAService() {
    let services = RecordingServices()
    for arguments in [[], ["bridge"], ["bridge", "dns"]] {
      XCTAssertEqual(FBBridgeCommand.run(arguments: arguments, services: services), 1)
    }
    XCTAssertTrue(services.calls.isEmpty)
  }

  func testCommandForwardsArgumentsAndExitStatus() {
    let services = RecordingServices()
    XCTAssertEqual(FBBridgeCommand.run(arguments: ["bridge", "dns", "set", "", "8.8.8.8"], services: services), 23)
    XCTAssertEqual(services.calls, [Call(service: "dns", action: "set", arguments: ["", "8.8.8.8"])])
  }

  func testEachRouteReceivesItsOriginalArgumentShape() {
    let services = RecordingServices()
    for service in ["contacts", "dns", "photos", "notifications", "health", "proxy", "accessibility"] {
      XCTAssertEqual(FBBridgeCommand.dispatch(service: service, action: "action", arguments: ["bundle", "type1", "type2"], services: services), 23)
    }
    XCTAssertEqual(
      services.calls,
      [
        Call(service: "contacts", action: "action", arguments: []),
        Call(service: "dns", action: "action", arguments: ["bundle", "type1", "type2"]),
        Call(service: "photos", action: "action", arguments: []),
        Call(service: "notifications", action: "action", arguments: ["bundle"]),
        Call(service: "health", action: "action", arguments: ["bundle", "type1", "type2"]),
        Call(service: "proxy", action: "action", arguments: ["bundle", "type1", "type2"]),
        Call(service: "accessibility", action: "action", arguments: ["bundle", "type1", "type2"]),
      ])
  }

  func testMissingBundleIDsRemainNil() {
    let services = RecordingServices()
    for service in ["notifications", "health"] {
      XCTAssertEqual(FBBridgeCommand.dispatch(service: service, action: "list", arguments: [], services: services), 23)
    }
    XCTAssertEqual(
      services.calls,
      [
        Call(service: "notifications", action: "list", arguments: [nil]),
        Call(service: "health", action: "list", arguments: [nil]),
      ])
  }

  func testInvalidServiceAndReplCommandsDoNotCallTheLoader() {
    let services = RecordingServices()
    XCTAssertEqual(FBBridgeCommand.dispatch(service: "unknown", action: "start", arguments: [], services: services), 1)
    for (action, arguments) in [("stop", ["socket", "library"]), ("start", []), ("start", ["socket"]), ("start", ["socket", ""])] {
      XCTAssertEqual(FBBridgeCommand.dispatch(service: "repl", action: action, arguments: arguments, services: services), 1)
    }
    XCTAssertTrue(services.calls.isEmpty)
  }

  func testReplForwardsOnlySocketAndLibraryPaths() {
    let services = RecordingServices()
    XCTAssertEqual(FBBridgeCommand.dispatch(service: "repl", action: "start", arguments: ["socket", "library", "ignored"], services: services), 23)
    XCTAssertEqual(services.calls, [Call(service: "repl", action: "start", arguments: ["socket", "library"])])
  }
}

private struct Call: Equatable {
  let service: String
  let action: String
  let arguments: [String?]
}

private final class RecordingServices: NSObject, FBBridgeServiceHandling {
  var calls: [Call] = []

  private func record(_ service: String, _ action: String, _ arguments: [String?]) -> Int32 {
    calls.append(Call(service: service, action: action, arguments: arguments))
    return 23
  }

  func contacts(_ action: String) -> Int32 { record("contacts", action, []) }
  func health(_ action: String, bundleID: String?, typeIDs: [String]) -> Int32 { record("health", action, [bundleID] + typeIDs.map { $0 }) }
  func dns(_ action: String, arguments: [String]) -> Int32 { record("dns", action, arguments) }
  func photos(_ action: String) -> Int32 { record("photos", action, []) }
  func notifications(_ action: String, bundleID: String?) -> Int32 { record("notifications", action, [bundleID]) }
  func proxy(_ action: String, arguments: [String]) -> Int32 { record("proxy", action, arguments) }
  func accessibility(_ action: String, arguments: [String]) -> Int32 { record("accessibility", action, arguments) }
  func repl(_ socketPath: String?, libraryPath: String) -> Int32 { record("repl", "start", [socketPath, libraryPath]) }
}
