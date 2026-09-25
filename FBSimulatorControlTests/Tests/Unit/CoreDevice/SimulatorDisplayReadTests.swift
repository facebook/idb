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

private func displayValue(id: String, active: Bool, primary: Bool = false, rotation: String = "rot0") -> xpc_object_t {
  let dictionary = SimulatorCoreDevice.dictionary
  let array = SimulatorCoreDevice.array
  return dictionary([
    "uniqueId": xpc_string_create(id), "name": xpc_string_create(id),
    "active": xpc_bool_create(active), "primary": xpc_bool_create(primary),
    "bounds": array([array([xpc_double_create(0), xpc_double_create(0)]), array([xpc_double_create(2007), xpc_double_create(2853)])]),
    "pointScale": xpc_int64_create(3), "currentOrientation": xpc_string_create(rotation),
    "type": dictionary(["integrated": dictionary([:])]),
  ])
}

private func displayReply(_ values: [xpc_object_t], current: Bool = true) -> xpc_object_t {
  SimulatorCoreDevice.dictionary([
    "CoreDevice.output": SimulatorCoreDevice.dictionary([
      "current": xpc_bool_create(current), "displays": SimulatorCoreDevice.array(values),
    ])
  ])
}

final class SimulatorDisplayReadTests: XCTestCase {
  func testLegacyGeometryRetainsInterfaceRotationWithoutInventingIdentity() throws {
    let value = displayValue(id: "legacy", active: true, rotation: "rot90")
    xpc_dictionary_set_value(value, "active", nil)
    xpc_dictionary_set_value(value, "uniqueId", nil)
    let selected = try SimulatorDisplayProtocol.interactionDisplay(displayReply([value]))
    guard case let .legacy(geometry) = selected else { return XCTFail("Expected legacy geometry") }
    XCTAssertEqual(geometry.pointSize, CGSize(width: 951, height: 669))
    XCTAssertEqual(try geometry.unrotatedPoint(from: CGPoint(x: 787, y: 570)), CGPoint(x: 570, y: 164))
    XCTAssertThrowsError(try SimulatorDisplayProtocol.interactionDisplay(displayReply([value, value])))
    XCTAssertThrowsError(try SimulatorDisplayProtocol.interactionDisplay(displayReply([value], current: false)))
    xpc_dictionary_set_string(value, "uniqueId", "partial")
    XCTAssertThrowsError(try SimulatorDisplayProtocol.interactionDisplay(displayReply([value])))
  }

  func testIdentifiedGeometryUsesActiveDisplayInsteadOfPrimary() throws {
    let selected = try SimulatorDisplayProtocol.interactionDisplay(
      displayReply([
        displayValue(id: "cover", active: false, primary: true),
        displayValue(id: "inner", active: true, rotation: "rot90"),
      ]))
    guard case let .identified(display) = selected else { return XCTFail("Expected identified display") }
    XCTAssertEqual(display.uniqueID, "inner")
    XCTAssertEqual(selected.geometry.pointSize, CGSize(width: 951, height: 669))
  }

  func testInterfacePointConversionPreservesAllFourRotations() throws {
    let cases: [(SimulatorDisplayRotation, CGPoint, CGPoint)] = [
      (.upright, CGPoint(x: 80, y: 120), CGPoint(x: 80, y: 120)),
      (.clockwise, CGPoint(x: 80, y: 120), CGPoint(x: 120, y: 320)),
      (.upsideDown, CGPoint(x: 80, y: 120), CGPoint(x: 520, y: 280)),
      (.counterclockwise, CGPoint(x: 80, y: 120), CGPoint(x: 480, y: 80)),
    ]
    for (rotation, point, expected) in cases {
      let geometry = SimulatorDisplayGeometry(bounds: CGRect(x: 30, y: 40, width: 1200, height: 800), scale: 2, rotation: rotation)
      XCTAssertEqual(try geometry.unrotatedPoint(from: point), expected)
      for invalid in [CGPoint(x: -1, y: 0), CGPoint(x: 1000, y: 0), CGPoint(x: Double.nan, y: 0)] {
        XCTAssertThrowsError(try geometry.unrotatedPoint(from: invalid))
      }
    }
  }

  func testLegacyReportWithoutIdentityOrActivityDeclinesCaptureCapability() throws {
    let value = displayValue(id: "legacy", active: true)
    xpc_dictionary_set_value(value, "active", nil)
    xpc_dictionary_set_value(value, "uniqueId", nil)
    XCTAssertEqual(try SimulatorDisplayProtocol.snapshot(displayReply([value])), .legacyProvider)
    XCTAssertThrowsError(try SimulatorDisplayProtocol.displays(displayReply([value])))
    XCTAssertThrowsError(try SimulatorDisplayProtocol.snapshot(displayReply([value], current: false)))
    // A legacy record is still held to the rest of the shape.
    xpc_dictionary_set_int64(value, "pointScale", 0)
    XCTAssertThrowsError(try SimulatorDisplayProtocol.snapshot(displayReply([value])))
  }

  func testPartialOrMalformedCaptureCapabilityDoesNotFallBack() {
    XCTAssertThrowsError(try SimulatorDisplayProtocol.snapshot(displayReply([SimulatorCoreDevice.dictionary([:])])))
    let partial = displayValue(id: "inner", active: true)
    xpc_dictionary_set_value(partial, "active", nil)
    XCTAssertThrowsError(try SimulatorDisplayProtocol.snapshot(displayReply([partial])))
    let malformed = displayValue(id: "inner", active: true)
    xpc_dictionary_set_string(malformed, "active", "true")
    XCTAssertThrowsError(try SimulatorDisplayProtocol.snapshot(displayReply([malformed])))
    let legacy = displayValue(id: "legacy", active: true)
    xpc_dictionary_set_value(legacy, "active", nil)
    xpc_dictionary_set_value(legacy, "uniqueId", nil)
    XCTAssertThrowsError(try SimulatorDisplayProtocol.snapshot(displayReply([displayValue(id: "inner", active: true), legacy])))
  }

  func testEmptyCurrentReportDoesNotFallBack() throws {
    guard case let .displays(displays) = try SimulatorDisplayProtocol.snapshot(displayReply([])) else {
      return XCTFail("An empty current report is not a legacy provider")
    }
    XCTAssertThrowsError(try SimulatorDisplayCommands.activeIntegratedDisplay(in: displays))
  }

  func testActivityEvidenceSourceCanChangeWithoutChangingDisplayConfiguration() throws {
    let value = displayValue(id: "inner", active: true, rotation: "rot90")
    xpc_dictionary_set_string(value, "backlightState", "activeOn")
    let layout = try SimulatorDisplayProtocol.interactionDisplay(displayReply([value]))
    xpc_dictionary_set_value(value, "active", nil)
    let backlight = try SimulatorDisplayProtocol.interactionDisplay(displayReply([value]))
    XCTAssertNotEqual(layout, backlight)
    XCTAssertTrue(layout.hasSameConfiguration(as: backlight))
    xpc_dictionary_set_string(value, "currentOrientation", "rot180")
    XCTAssertFalse(layout.hasSameConfiguration(as: try SimulatorDisplayProtocol.interactionDisplay(displayReply([value]))))
  }

  func testCompleteBacklightEvidenceSelectsIlluminatedDisplayWithoutInventingLayoutActivity() throws {
    for state in ["activeOn", "activeDimmed"] {
      let cover = displayValue(id: "cover", active: false, primary: true)
      let inner = displayValue(id: "inner", active: true)
      for value in [cover, inner] { xpc_dictionary_set_value(value, "active", nil) }
      xpc_dictionary_set_string(cover, "backlightState", "off")
      xpc_dictionary_set_string(inner, "backlightState", state)
      let displays = try SimulatorDisplayProtocol.displays(displayReply([cover, inner]))
      let selected = try SimulatorDisplayCommands.activeIntegratedDisplay(in: displays)
      XCTAssertEqual(selected.uniqueID, "inner")
      XCTAssertEqual(selected.activitySource, .backlight)
      XCTAssertNil(selected.reportedActivity)
    }
  }

  func testBacklightSelectionRejectsUncertaintyAmbiguityAndPartialLayoutActivity() throws {
    let cover = displayValue(id: "cover", active: false, primary: true)
    let inner = displayValue(id: "inner", active: true)
    for value in [cover, inner] { xpc_dictionary_set_value(value, "active", nil) }
    for (first, second) in [("off", "off"), ("inactiveOn", "off"), ("unknown", "activeOn"), ("activeOn", "activeDimmed"), ("off", "futureState")] {
      xpc_dictionary_set_string(cover, "backlightState", first)
      xpc_dictionary_set_string(inner, "backlightState", second)
      XCTAssertThrowsError(try SimulatorDisplayProtocol.interactionDisplay(displayReply([cover, inner])))
    }
    xpc_dictionary_set_string(cover, "backlightState", "off")
    xpc_dictionary_set_string(inner, "backlightState", "activeOn")
    xpc_dictionary_set_bool(cover, "active", false)
    XCTAssertThrowsError(try SimulatorDisplayProtocol.displays(displayReply([cover, inner])))
    xpc_dictionary_set_bool(inner, "active", false)
    XCTAssertThrowsError(try SimulatorDisplayProtocol.displays(displayReply([cover, inner])))
    xpc_dictionary_set_bool(inner, "active", true)
    let selected = try SimulatorDisplayCommands.activeIntegratedDisplay(in: SimulatorDisplayProtocol.displays(displayReply([cover, inner])))
    XCTAssertEqual(selected.activitySource, .layout)
    XCTAssertEqual(selected.reportedActivity, true)
  }

  func testDisplayStringsAreBounded() {
    let long = String(repeating: "x", count: 1025)
    for key in ["uniqueId", "name"] {
      let value = displayValue(id: "inner", active: true)
      xpc_dictionary_set_string(value, key, long)
      XCTAssertThrowsError(try SimulatorDisplayProtocol.displays(displayReply([value])), key)
    }
    XCTAssertThrowsError(try SimulatorDisplayProtocol.displays(displayReply([displayValue(id: "", active: true)])))
  }

  func testExplicitActivitySelectsInnerDespiteNonemptyPrimaryBounds() throws {
    let displays = try SimulatorDisplayProtocol.displays(
      displayReply([
        displayValue(id: "cover", active: false, primary: true),
        displayValue(id: "inner", active: true, rotation: "rot90"),
      ]))
    let selected = try SimulatorDisplayCommands.activeIntegratedDisplay(in: displays)
    XCTAssertEqual(selected.uniqueID, "inner")
    XCTAssertEqual(selected.size, CGSize(width: 2853, height: 2007))
    XCTAssertEqual(selected.scale, 3)
  }

  func testActivityCannotBeInferredFromMissingFieldOrStaleReport() {
    let value = displayValue(id: "cover", active: true, primary: true)
    XCTAssertThrowsError(try SimulatorDisplayProtocol.displays(displayReply([value], current: false)))
    xpc_dictionary_set_value(value, "active", nil)
    XCTAssertThrowsError(try SimulatorDisplayProtocol.displays(displayReply([value])))
  }

  func testAmbiguousAndMissingActiveIntegratedDisplaysFail() throws {
    let values = [displayValue(id: "cover", active: true), displayValue(id: "inner", active: true)]
    let displays = try SimulatorDisplayProtocol.displays(displayReply(values))
    XCTAssertThrowsError(try SimulatorDisplayCommands.activeIntegratedDisplay(in: displays))
    XCTAssertThrowsError(try SimulatorDisplayCommands.activeIntegratedDisplay(in: []))
    XCTAssertThrowsError(try SimulatorDisplayProtocol.displays(displayReply([values[0], values[0]])))
  }

  func testRotationAndScaleMustBeRecognized() {
    XCTAssertThrowsError(try SimulatorDisplayProtocol.displays(displayReply([displayValue(id: "inner", active: true, rotation: "unknown")])))
    let value = displayValue(id: "inner", active: true)
    xpc_dictionary_set_int64(value, "pointScale", 0)
    XCTAssertThrowsError(try SimulatorDisplayProtocol.displays(displayReply([value])))
  }

  func testActiveBoundsMustBeNonemptyAndFinite() {
    for width in [0, -1, Double.nan, Double.infinity] {
      let value = displayValue(id: "inner", active: true)
      xpc_dictionary_set_value(
        value, "bounds",
        SimulatorCoreDevice.array([
          SimulatorCoreDevice.array([xpc_double_create(0), xpc_double_create(0)]),
          SimulatorCoreDevice.array([xpc_double_create(width), xpc_double_create(2007)]),
        ]))
      XCTAssertThrowsError(try SimulatorDisplayProtocol.displays(displayReply([value])))
    }
  }

  private func readDisplays(from services: SyntheticXPCServices, timeout: DispatchTimeInterval = .seconds(5)) async throws -> [SimulatorDisplay] {
    let channel = try services.channel(to: SimulatorDisplayProtocol.service)
    return try await CoreDeviceSession<[SimulatorDisplay]>(channel: channel, timeout: timeout)
      .read(SimulatorCoreDevice.dictionary([:]), decode: SimulatorDisplayProtocol.displays)
  }

  func testSnapshotCompletesAndClosesTheConnection() async throws {
    let services = SyntheticXPCServices()
    let peer = services.register(
      SimulatorDisplayProtocol.service, respond: SyntheticXPCPeer.replying(displayReply([displayValue(id: "inner", active: true)])))
    let result = try await readDisplays(from: services)
    XCTAssertEqual(result.map(\.uniqueID), ["inner"])
    XCTAssertEqual(peer.received.count, 1)
    let closed = await peer.closed(atLeast: 1)
    XCTAssertEqual(closed, 1)
  }

  func testTimeoutDoesNotProduceEmptySuccess() async {
    let services = SyntheticXPCServices()
    let peer = services.register(SimulatorDisplayProtocol.service, respond: SyntheticXPCPeer.silent)
    do {
      _ = try await readDisplays(from: services, timeout: .milliseconds(500))
      XCTFail("Expected a failed snapshot")
    } catch {
      guard case SimulatorCoreDeviceError.timedOut = error else { return XCTFail("Unexpected error: \(error)") }
    }
    let closed = await peer.closed(atLeast: 1)
    XCTAssertEqual(closed, 1)
  }

  func testPeerLossDoesNotProduceEmptySuccess() async {
    let services = SyntheticXPCServices()
    services.register(SimulatorDisplayProtocol.service) { $0.interrupt() }
    do {
      _ = try await readDisplays(from: services)
      XCTFail("Expected a failed snapshot")
    } catch {
      guard case SimulatorCoreDeviceError.unavailable = error else { return XCTFail("Unexpected error: \(error)") }
    }
  }

  func testProviderErrorIsPropagated() async {
    let services = SyntheticXPCServices()
    let peer = services.register(
      SimulatorDisplayProtocol.service,
      respond: SyntheticXPCPeer.replying(
        SimulatorCoreDevice.dictionary([
          "CoreDevice.error": SimulatorCoreDevice.dictionary([
            "domain": xpc_string_create("provider"), "code": xpc_int64_create(42),
          ])
        ])))
    do {
      _ = try await readDisplays(from: services)
      XCTFail("Expected provider failure")
    } catch { XCTAssertTrue(error.localizedDescription.contains("provider (42)")) }
    let closed = await peer.closed(atLeast: 1)
    XCTAssertEqual(closed, 1)
  }

  func testCancellationClosesOutstandingSnapshot() async {
    let services = SyntheticXPCServices()
    let peer = services.register(SimulatorDisplayProtocol.service, respond: SyntheticXPCPeer.silent)
    let task = Task { try await readDisplays(from: services) }
    _ = await peer.received(atLeast: 1)
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch { XCTAssertTrue(error is CancellationError) }
    let closed = await peer.closed(atLeast: 1)
    XCTAssertEqual(closed, 1)
  }
}
