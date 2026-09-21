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

// SAFETY: The request session invokes every transport method and test script on its serial queue.
// patternlint-disable-next-line unchecked-sendable
private final class DisplayTransportStub: SimulatorCoreDeviceTransport, @unchecked Sendable {
  let script: @Sendable (DisplayTransportStub) -> Void
  var reply: (@Sendable (xpc_object_t) -> Void)?
  var event: (@Sendable (xpc_object_t) -> Void)?
  var cancellations = 0

  init(script: @escaping @Sendable (DisplayTransportStub) -> Void) { self.script = script }

  func start(request: xpc_object_t, event: @escaping @Sendable (xpc_object_t) -> Void, reply: @escaping @Sendable (xpc_object_t) -> Void) {
    self.reply = reply
    self.event = event
    script(self)
  }

  func acknowledge(_ event: xpc_object_t, cancelling: Bool) { XCTFail("Snapshot must not acknowledge a stream") }
  func cancel() { cancellations += 1 }
}

final class SimulatorDisplayReadTests: XCTestCase {
  func testLegacyReportWithoutIdentityOrActivityDeclinesCaptureCapability() throws {
    let value = displayValue(id: "legacy", active: true)
    xpc_dictionary_set_value(value, "active", nil)
    xpc_dictionary_set_value(value, "uniqueId", nil)
    XCTAssertNil(try SimulatorDisplayProtocol.captureDisplays(displayReply([value])))
    XCTAssertThrowsError(try SimulatorDisplayProtocol.displays(displayReply([value])))
    XCTAssertThrowsError(try SimulatorDisplayProtocol.captureDisplays(displayReply([value], current: false)))
  }

  func testPartialOrMalformedCaptureCapabilityDoesNotFallBack() {
    XCTAssertThrowsError(try SimulatorDisplayProtocol.captureDisplays(displayReply([SimulatorCoreDevice.dictionary([:])])))
    let partial = displayValue(id: "inner", active: true)
    xpc_dictionary_set_value(partial, "active", nil)
    XCTAssertThrowsError(try SimulatorDisplayProtocol.captureDisplays(displayReply([partial])))
    let malformed = displayValue(id: "inner", active: true)
    xpc_dictionary_set_string(malformed, "active", "true")
    XCTAssertThrowsError(try SimulatorDisplayProtocol.captureDisplays(displayReply([malformed])))
    let legacy = displayValue(id: "legacy", active: true)
    xpc_dictionary_set_value(legacy, "active", nil)
    xpc_dictionary_set_value(legacy, "uniqueId", nil)
    XCTAssertThrowsError(try SimulatorDisplayProtocol.captureDisplays(displayReply([displayValue(id: "inner", active: true), legacy])))
  }

  func testEmptyCurrentReportDoesNotFallBack() throws {
    let displays = try XCTUnwrap(SimulatorDisplayProtocol.captureDisplays(displayReply([])))
    XCTAssertThrowsError(try SimulatorDisplayCommands.activeIntegratedDisplay(in: displays))
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

  func testSnapshotCompletesOnceAndClosesTransport() async throws {
    let queue = DispatchQueue(label: #function)
    let transport = DisplayTransportStub { transport in
      transport.reply?(displayReply([displayValue(id: "inner", active: true)]))
      transport.reply?(displayReply([]))
      transport.event?(XPC_ERROR_CONNECTION_INVALID)
    }
    let operation = SimulatorCoreDeviceRequest<[SimulatorDisplay]>(transport: transport, queue: queue)
    let result = try await operation.read(SimulatorCoreDevice.dictionary([:]), decode: SimulatorDisplayProtocol.displays)
    XCTAssertEqual(result.map(\.uniqueID), ["inner"])
    XCTAssertEqual(queue.sync { transport.cancellations }, 1)
  }

  func testTimeoutAndPeerLossDoNotProduceEmptySuccess() async {
    for peerLoss in [false, true] {
      let queue = DispatchQueue(label: #function)
      let transport = DisplayTransportStub { transport in
        if peerLoss { transport.event?(XPC_ERROR_CONNECTION_INVALID) }
      }
      let operation = SimulatorCoreDeviceRequest<[SimulatorDisplay]>(transport: transport, queue: queue, timeout: .milliseconds(10))
      do {
        _ = try await operation.read(SimulatorCoreDevice.dictionary([:]), decode: SimulatorDisplayProtocol.displays)
        XCTFail("Expected a failed snapshot")
      } catch { XCTAssertTrue(error is SimulatorCoreDeviceError) }
      XCTAssertEqual(queue.sync { transport.cancellations }, 1)
    }
  }

  func testProviderErrorIsPropagated() async {
    let queue = DispatchQueue(label: #function)
    let transport = DisplayTransportStub { transport in
      transport.reply?(
        SimulatorCoreDevice.dictionary([
          "CoreDevice.error": SimulatorCoreDevice.dictionary([
            "domain": xpc_string_create("provider"), "code": xpc_int64_create(42),
          ])
        ]))
    }
    let operation = SimulatorCoreDeviceRequest<[SimulatorDisplay]>(transport: transport, queue: queue)
    do {
      _ = try await operation.read(SimulatorCoreDevice.dictionary([:]), decode: SimulatorDisplayProtocol.displays)
      XCTFail("Expected provider failure")
    } catch { XCTAssertTrue(error.localizedDescription.contains("provider (42)")) }
    XCTAssertEqual(queue.sync { transport.cancellations }, 1)
  }

  func testCancellationClosesOutstandingSnapshot() async {
    let queue = DispatchQueue(label: #function)
    let transport = DisplayTransportStub { _ in }
    let operation = SimulatorCoreDeviceRequest<[SimulatorDisplay]>(transport: transport, queue: queue)
    let task = Task { try await operation.read(SimulatorCoreDevice.dictionary([:]), decode: SimulatorDisplayProtocol.displays) }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(queue.sync { transport.cancellations }, 1)
  }
}
