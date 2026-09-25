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

private func hingeEvent(channel: UUID, degrees: Double = 130, timestamp: Double = 200, valid: Bool = true, unit: String = "°") -> xpc_object_t {
  let dictionary = SimulatorCoreDevice.dictionary
  return hingeEvent(
    channel: channel,
    elements: [
      dictionary([
        "angle": dictionary([
          "value": xpc_double_create(degrees),
          "unit": dictionary([
            "symbol": xpc_string_create(unit),
            "converter": dictionary(["coefficient": xpc_double_create(1), "constant": xpc_double_create(0)]),
          ]),
        ]),
        "timestamp": xpc_double_create(timestamp),
        "isAngleValid": xpc_bool_create(valid),
      ])
    ])
}

private func hingeEvent(channel: UUID, elements: [xpc_object_t]) -> xpc_object_t {
  let dictionary = SimulatorCoreDevice.dictionary
  return dictionary([
    "XPCSideChannel.uniqueIdentifier": xpc_string_create(channel.uuidString),
    "CoreDevice.XPCMessageKey.sideChannelStatus": dictionary([
      "pushing": dictionary(["elements": SimulatorCoreDevice.array(elements)])
    ]),
  ])
}

/// The stream request as the client encodes it for the hinge command.
private func hingeRequest(channel: UUID) throws -> xpc_object_t {
  try CoreDeviceRequest(
    action: SimulatorHingeProtocol.action, deviceID: "device", version: CoreDeviceVersion("651.13.4"),
    input: SimulatorHingeProtocol.StreamInput(channel: channel)
  ).encoded()
}

// SAFETY: All state, including the test script and callbacks, is accessed on the session queue.
// patternlint-disable-next-line unchecked-sendable
private final class HingeTransportStub: SimulatorCoreDeviceTransport, @unchecked Sendable {
  let script: @Sendable (HingeTransportStub) -> Void
  var event: (@Sendable (xpc_object_t) -> Void)?
  var reply: (@Sendable (xpc_object_t) -> Void)?
  var acknowledgements: [Bool] = []
  var cancellations = 0
  var completesCancellation = true

  init(script: @escaping @Sendable (HingeTransportStub) -> Void) { self.script = script }

  func start(request: xpc_object_t, event: @escaping @Sendable (xpc_object_t) -> Void, reply: @escaping @Sendable (xpc_object_t) -> Void) {
    self.event = event
    self.reply = reply
    script(self)
  }

  func acknowledge(_ event: xpc_object_t, cancelling: Bool) {
    acknowledgements.append(cancelling)
    if cancelling && completesCancellation { complete() }
  }

  func complete() {
    reply?(SimulatorCoreDevice.dictionary(["CoreDevice.output": xpc_dictionary_create(nil, nil, 0)]))
  }

  func cancel() { cancellations += 1 }
}

final class SimulatorHingeReadTests: XCTestCase {
  func testRequestUsesNativeUUIDAndUnsignedDurationLowBits() throws {
    let channel = UUID()
    let request = try hingeRequest(channel: channel)
    XCTAssertEqual(String(cString: xpc_dictionary_get_string(request, "CoreDevice.actionIdentifier")!), SimulatorHingeProtocol.action)
    let version = try XCTUnwrap(xpc_dictionary_get_dictionary(request, "CoreDevice.coreDeviceVersion"))
    let components = try XCTUnwrap(xpc_dictionary_get_array(version, "components"))
    XCTAssertEqual(xpc_array_get_count(components), 3)
    XCTAssertEqual(xpc_get_type(xpc_array_get_value(components, 0)), XPC_TYPE_UINT64)
    XCTAssertEqual(xpc_array_get_uint64(components, 0), 651)
    let input = try XCTUnwrap(xpc_dictionary_get_dictionary(request, "CoreDevice.input"))
    let proxy = try XCTUnwrap(xpc_dictionary_get_dictionary(input, "streamProxy"))
    let identifier = try XCTUnwrap(xpc_dictionary_get_value(proxy, "sideChannel"))
    XCTAssertEqual(xpc_get_type(identifier), XPC_TYPE_UUID)
    let config = try XCTUnwrap(xpc_dictionary_get_dictionary(input, "actualInput"))
    let interval = try XCTUnwrap(xpc_dictionary_get_array(config, "updateInterval"))
    XCTAssertEqual(xpc_get_type(xpc_array_get_value(interval, 0)), XPC_TYPE_INT64)
    XCTAssertEqual(xpc_get_type(xpc_array_get_value(interval, 1)), XPC_TYPE_UINT64)
    XCTAssertEqual(xpc_array_get_uint64(interval, 1), 100_000_000_000_000_000)
    XCTAssertThrowsError(try CoreDeviceVersion("651..4"))
  }

  func testAcceptsMeasuredIntermediateAngle() throws {
    let channel = UUID()
    let angle = try SimulatorHingeProtocol.sample(hingeEvent(channel: channel, degrees: 121.64), channel: channel, notBefore: 199, now: 201)
    XCTAssertEqual(angle?.degrees, 121.64)
  }

  func testIgnoresStaleAndInvalidSamples() throws {
    let channel = UUID()
    XCTAssertNil(try SimulatorHingeProtocol.sample(hingeEvent(channel: channel, timestamp: 198), channel: channel, notBefore: 199, now: 201))
    XCTAssertNil(try SimulatorHingeProtocol.sample(hingeEvent(channel: channel, valid: false), channel: channel, notBefore: 199, now: 201))
  }

  func testSkippedSamplesAreNotRead() throws {
    let channel = UUID()
    let junk = xpc_string_create("junk")
    let invalid = SimulatorCoreDevice.dictionary(["isAngleValid": xpc_bool_create(false), "timestamp": junk, "angle": junk])
    let stale = SimulatorCoreDevice.dictionary(["isAngleValid": xpc_bool_create(true), "timestamp": xpc_double_create(198), "angle": junk])
    let event = hingeEvent(channel: channel, elements: [invalid, stale])
    XCTAssertNil(try SimulatorHingeProtocol.sample(event, channel: channel, notBefore: 199, now: 201))
  }

  func testRejectsBadValuesAndFutureTimestamps() {
    let channel = UUID()
    for degrees in [-1, 181, Double.nan, .infinity] {
      XCTAssertThrowsError(try SimulatorHingeProtocol.sample(hingeEvent(channel: channel, degrees: degrees), channel: channel, notBefore: 199, now: 201))
    }
    XCTAssertThrowsError(try SimulatorHingeProtocol.sample(hingeEvent(channel: channel, timestamp: 202), channel: channel, notBefore: 199, now: 201))
    XCTAssertThrowsError(try SimulatorHingeProtocol.sample(hingeEvent(channel: channel, unit: "rad"), channel: channel, notBefore: 199, now: 201))
    XCTAssertThrowsError(try SimulatorHingeProtocol.sample(hingeEvent(channel: channel), channel: UUID(), notBefore: 199, now: 201))
  }

  // MARK: - Streaming through the session

  /// A hinge read as `SimulatorHingeCommands` performs it: a stream that samples until a fresh
  /// angle arrives, with the clock pinned so timestamps are deterministic.
  private func readAngle(
    _ transport: HingeTransportStub, queue: DispatchQueue, channel: UUID = UUID(), timeout: DispatchTimeInterval = .seconds(5)
  ) async throws -> SimulatorHingeAngle {
    let request = try hingeRequest(channel: channel)
    return try await CoreDeviceSession<SimulatorHingeAngle>(transport: transport, queue: queue, timeout: timeout).stream(request) { event in
      try SimulatorHingeProtocol.sample(event, channel: channel, notBefore: 200, now: 200)
    }
  }

  func testStaleInitialSampleDoesNotCompleteRead() async throws {
    let channel = UUID()
    let queue = DispatchQueue(label: "hinge-read-test")
    let transport = HingeTransportStub { transport in
      transport.event?(hingeEvent(channel: channel, degrees: 180, timestamp: 199))
      transport.event?(hingeEvent(channel: channel, degrees: 0))
      transport.event?(hingeEvent(channel: channel, degrees: 90))
      transport.complete()
    }
    let angle = try await readAngle(transport, queue: queue, channel: channel)
    XCTAssertEqual(angle.degrees, 0)
    queue.sync {
      XCTAssertEqual(transport.acknowledgements, [false, true])
      XCTAssertEqual(transport.cancellations, 1)
    }
  }

  func testProviderMustFinishCancellationBeforeReadCompletes() async {
    let channel = UUID()
    let queue = DispatchQueue(label: "hinge-read-test")
    let transport = HingeTransportStub { transport in
      transport.completesCancellation = false
      transport.event?(hingeEvent(channel: channel))
    }
    do {
      _ = try await readAngle(transport, queue: queue, channel: channel, timeout: .milliseconds(10))
      XCTFail("Expected timeout awaiting provider cancellation")
    } catch {
      guard case SimulatorCoreDeviceError.timedOut = error else { return XCTFail("Unexpected error: \(error)") }
    }
    queue.sync { XCTAssertEqual(transport.cancellations, 1) }
  }

  func testPrematureCompletionIsAnError() async {
    let queue = DispatchQueue(label: "hinge-read-test")
    let transport = HingeTransportStub { $0.complete() }
    do {
      _ = try await readAngle(transport, queue: queue)
      XCTFail("Expected missing sample error")
    } catch {
      guard case SimulatorCoreDeviceError.unavailable = error else { return XCTFail("Unexpected error: \(error)") }
    }
    queue.sync { XCTAssertEqual(transport.cancellations, 1) }
  }

  func testAProviderErrorInTheFinalReplyFails() async {
    let channel = UUID()
    let queue = DispatchQueue(label: "hinge-read-test")
    let transport = HingeTransportStub { transport in
      transport.completesCancellation = false
      transport.event?(hingeEvent(channel: channel))
      transport.reply?(
        SimulatorCoreDevice.dictionary([
          "CoreDevice.error": SimulatorCoreDevice.dictionary(["domain": xpc_string_create("com.example"), "code": xpc_int64_create(9)])
        ]))
    }
    do {
      _ = try await readAngle(transport, queue: queue, channel: channel)
      XCTFail("Expected provider error")
    } catch {
      guard case let SimulatorCoreDeviceError.unavailable(detail) = error else { return XCTFail("Unexpected error: \(error)") }
      XCTAssertEqual(detail, "com.example (9)")
    }
  }

  func testPeerLossWhileAwaitingCancellationFails() async {
    let channel = UUID()
    let queue = DispatchQueue(label: "hinge-read-test")
    let transport = HingeTransportStub { transport in
      transport.completesCancellation = false
      transport.event?(hingeEvent(channel: channel))
      transport.event?(XPC_ERROR_CONNECTION_INVALID)
    }
    do {
      _ = try await readAngle(transport, queue: queue, channel: channel)
      XCTFail("Expected connection error")
    } catch {
      guard case SimulatorCoreDeviceError.unavailable = error else { return XCTFail("Unexpected error: \(error)") }
    }
    queue.sync { XCTAssertEqual(transport.cancellations, 1) }
  }

  func testCancellationBeforeSetupDoesNotStartRequest() async {
    let queue = DispatchQueue(label: "hinge-read-test")
    let transport = HingeTransportStub { _ in XCTFail("Cancelled request started") }
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await readAngle(transport, queue: queue)
    }
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch { XCTAssertTrue(error is CancellationError) }
    queue.sync { XCTAssertEqual(transport.cancellations, 1) }
  }

  func testCancellationClosesAnIdleConnection() async {
    let started = expectation(description: "request started")
    let queue = DispatchQueue(label: "hinge-read-test")
    let transport = HingeTransportStub { _ in started.fulfill() }
    let task = Task { try await readAngle(transport, queue: queue) }
    await fulfillment(of: [started], timeout: 2)
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch { XCTAssertTrue(error is CancellationError) }
    queue.sync { XCTAssertEqual(transport.cancellations, 1) }
  }
}
