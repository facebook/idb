/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import XCTest
@preconcurrency import XPC

private func displayValue(id: String, active: Bool) -> xpc_object_t {
  let dictionary = SimulatorCoreDevice.dictionary
  let array = SimulatorCoreDevice.array
  return dictionary([
    "uniqueId": xpc_string_create(id), "name": xpc_string_create(id),
    "active": xpc_bool_create(active), "primary": xpc_bool_create(false),
    "bounds": array([array([xpc_double_create(0), xpc_double_create(0)]), array([xpc_double_create(2007), xpc_double_create(2853)])]),
    "pointScale": xpc_int64_create(3), "currentOrientation": xpc_string_create("rot0"),
    "type": dictionary(["integrated": dictionary([:])]),
  ])
}

private func report(_ displays: [xpc_object_t]) -> xpc_object_t {
  SimulatorCoreDevice.dictionary(["current": xpc_bool_create(true), "displays": SimulatorCoreDevice.array(displays)])
}

private func push(channel: UUID, _ reports: [xpc_object_t]) -> xpc_object_t {
  let dictionary = SimulatorCoreDevice.dictionary
  return dictionary([
    "XPCSideChannel.uniqueIdentifier": xpc_string_create(channel.uuidString),
    "CoreDevice.XPCMessageKey.sideChannelStatus": dictionary(["pushing": dictionary(["elements": SimulatorCoreDevice.array(reports)])]),
  ])
}

private func display(_ id: String) -> SimulatorDisplay {
  SimulatorDisplay(
    uniqueID: id, name: id, activity: .active, isPrimary: false, isIntegrated: true,
    bounds: CGRect(x: 0, y: 0, width: 1200, height: 800), scale: 2, rotation: .upright)
}

private struct Unsupported: Error {}

final class SimulatorDisplayUpdatesTests: XCTestCase {

  func testRequestNamesTheSideChannelAndTakesNoInput() throws {
    let channel = UUID()
    let request = try CoreDeviceRequest(
      action: SimulatorDisplayUpdatesProtocol.action, deviceID: "device", version: CoreDeviceVersion("651.13.4"),
      input: SimulatorDisplayUpdatesProtocol.StreamInput(channel: channel)
    ).encoded()
    let input = try XCTUnwrap(xpc_dictionary_get_dictionary(request, "CoreDevice.input"))
    let proxy = try XCTUnwrap(xpc_dictionary_get_dictionary(input, "streamProxy"))
    let identifier = try XCTUnwrap(xpc_dictionary_get_value(proxy, "sideChannel"))
    XCTAssertEqual(xpc_get_type(identifier), XPC_TYPE_UUID)
    let actualInput = try XCTUnwrap(xpc_dictionary_get_dictionary(input, "actualInput"))
    XCTAssertEqual(xpc_dictionary_get_count(actualInput), 0)
  }

  func testTheLatestReportInAPushSelectsTheActiveDisplay() throws {
    let channel = UUID()
    let target = try SimulatorDisplayUpdatesProtocol.target(
      push(
        channel: channel,
        [
          report([displayValue(id: "cover", active: true), displayValue(id: "inner", active: false)]),
          report([displayValue(id: "cover", active: false), displayValue(id: "inner", active: true)]),
        ]), channel: channel)
    guard case let .selected(inner)? = target else { return XCTFail("Expected a selected display, got \(String(describing: target))") }
    XCTAssertEqual(inner.uniqueID, "inner")
  }

  func testAPushThatCannotSelectADisplayYieldsNothing() throws {
    let channel = UUID()
    let noneActive = report([displayValue(id: "cover", active: false), displayValue(id: "inner", active: false)])
    XCTAssertNil(try SimulatorDisplayUpdatesProtocol.target(push(channel: channel, [noneActive]), channel: channel))
    XCTAssertNil(try SimulatorDisplayUpdatesProtocol.target(push(channel: channel, []), channel: channel))
  }

  func testAPushOnAnotherSideChannelIsMalformed() {
    let pushed = push(channel: UUID(), [report([displayValue(id: "lcd", active: true)])])
    XCTAssertThrowsError(try SimulatorDisplayUpdatesProtocol.target(pushed, channel: UUID()))
  }

  // MARK: - Following

  private func collect(_ updates: AsyncStream<SimulatorDisplay>, count: Int) async -> [String] {
    var ids: [String] = []
    for await display in updates {
      ids.append(display.uniqueID)
      if ids.count == count { break }
    }
    return ids
  }

  private func pushes(_ targets: [SimulatorDisplayTarget], then end: Error? = nil) -> AsyncThrowingStream<SimulatorDisplayTarget, Error> {
    AsyncThrowingStream { continuation in
      targets.forEach { continuation.yield($0) }
      continuation.finish(throwing: end)
    }
  }

  private func polling(_ ids: String...) -> AsyncStream<SimulatorDisplay> {
    AsyncStream { continuation in
      ids.forEach { continuation.yield(display($0)) }
    }
  }

  func testPushedSelectionsAreFollowedAndASoleDisplayIsSkipped() async {
    let updates = SimulatorDisplayCommands.activeDisplayUpdates(
      pushes: { self.pushes([.selected(display("inner")), .sole(.identified(display("lcd"))), .selected(display("cover"))]) },
      polling: { self.polling("polled") }, logger: nil)
    let ids = await collect(updates, count: 3)
    XCTAssertEqual(ids, ["inner", "cover", "polled"])
  }

  func testPollsWhenTheRuntimeDoesNotPush() async {
    let updates = SimulatorDisplayCommands.activeDisplayUpdates(
      pushes: { throw Unsupported() }, polling: { self.polling("cover", "inner") }, logger: nil)
    let ids = await collect(updates, count: 2)
    XCTAssertEqual(ids, ["cover", "inner"])
  }

  func testPollsWhenPushesFail() async {
    let updates = SimulatorDisplayCommands.activeDisplayUpdates(
      pushes: { self.pushes([.selected(display("inner"))], then: SimulatorCoreDeviceError.unavailable("gone")) },
      polling: { self.polling("cover") }, logger: nil)
    let ids = await collect(updates, count: 2)
    XCTAssertEqual(ids, ["inner", "cover"])
  }
}
