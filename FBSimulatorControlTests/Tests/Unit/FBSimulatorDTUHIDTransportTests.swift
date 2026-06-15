/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
@testable import FBSimulatorControl
import XCTest
import XPC

final class FBSimulatorDTUHIDTransportTests: XCTestCase {

  // MARK: Wire encoding (model + XPCEncoder, no connection needed)

  func testDigitizerEventEnvelopeShape() throws {
    let event = try encodeDigitizer(
      IndigoDigitizerEvent(pointOne: DigitizerPoint(x: 0.25, y: 0.75), eventType: .start))

    XCTAssertEqual(xpc_get_type(event), XPC_TYPE_DICTIONARY)
    XCTAssertEqual(messageString(event, "messageType"), "IndigoDigitizerEvent")
    XCTAssertEqual(messageString(event, "featureIdentifier"), FBSimulatorDTUHIDTransport.digitizerServiceName)

    // isBarrier must be an XPC bool, false.
    XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(event, "isBarrier")!), XPC_TYPE_BOOL)
    XCTAssertFalse(xpc_dictionary_get_bool(event, "isBarrier"))

    let payload = xpc_dictionary_get_dictionary(event, "payload")
    XCTAssertNotNil(payload)
    let pointOne = xpc_dictionary_get_dictionary(payload!, "pointOne")
    XCTAssertNotNil(pointOne)

    // Coordinates are XPC doubles.
    XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(pointOne!, "x")!), XPC_TYPE_DOUBLE)
    XCTAssertEqual(xpc_dictionary_get_double(pointOne!, "x"), 0.25, accuracy: 1e-9)
    XCTAssertEqual(xpc_dictionary_get_double(pointOne!, "y"), 0.75, accuracy: 1e-9)

    // Single-finger touch: the nil pointTwo writes no key.
    XCTAssertNil(xpc_dictionary_get_dictionary(payload!, "pointTwo"))
  }

  func testDigitizerEventIntegersAreUInt64() throws {
    // Decode-critical: dtuhidd's Swift Codable rejects these fields if sent as strings.
    let event = try encodeDigitizer(
      IndigoDigitizerEvent(pointOne: DigitizerPoint(x: 0.1, y: 0.2), eventType: .end))
    let payload = xpc_dictionary_get_dictionary(event, "payload")!
    for key in ["eventType", "edge", "target"] {
      XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(payload, key)!), XPC_TYPE_UINT64, "\(key) must be uint64")
    }
    XCTAssertEqual(xpc_dictionary_get_uint64(payload, "eventType"), 2) // .end
    XCTAssertEqual(xpc_dictionary_get_uint64(payload, "edge"), 0)
    XCTAssertEqual(xpc_dictionary_get_uint64(payload, "target"), 0)
  }

  // MARK: Contact-state machine

  func testContactTrackerMapsDownUpToStartPositionEnd() {
    var tracker = DigitizerContactTracker()
    XCTAssertEqual(tracker.eventType(for: .down), .start)
    XCTAssertEqual(tracker.eventType(for: .down), .position)
    XCTAssertEqual(tracker.eventType(for: .down), .position)
    XCTAssertEqual(tracker.eventType(for: .up), .end)
    // A subsequent gesture starts fresh.
    XCTAssertEqual(tracker.eventType(for: .down), .start)
    XCTAssertEqual(tracker.eventType(for: .up), .end)
  }

  func testDigitizerEventTypeRawValues() {
    XCTAssertEqual(DigitizerEventType.start.rawValue, 0)
    XCTAssertEqual(DigitizerEventType.position.rawValue, 1)
    XCTAssertEqual(DigitizerEventType.end.rawValue, 2)
  }

  // MARK: Normalization parity with the Indigo transport

  func testNormalizationParityWithIndigoRatio() throws {
    let screenSize = CGSize(width: 1170, height: 2532) // pixels
    let scale: Float = 3.0
    let point = CGPoint(x: 201, y: 482) // points

    let ratio = FBSimulatorIndigoHID.screenRatio(from: point, screenSize: screenSize, screenScale: scale)
    // The DTUHID transport feeds exactly this ratio into pointOne.
    let event = try encodeDigitizer(
      IndigoDigitizerEvent(pointOne: DigitizerPoint(x: Double(ratio.x), y: Double(ratio.y)), eventType: .start))
    let pointOne = xpc_dictionary_get_dictionary(xpc_dictionary_get_dictionary(event, "payload")!, "pointOne")!

    XCTAssertEqual(xpc_dictionary_get_double(pointOne, "x"), Double(ratio.x), accuracy: 1e-9)
    XCTAssertEqual(xpc_dictionary_get_double(pointOne, "y"), Double(ratio.y), accuracy: 1e-9)
    // Sanity: point * scale / pixels == point / points, in 0...1.
    XCTAssertEqual(Double(ratio.x), 201.0 * 3.0 / 1170.0, accuracy: 1e-9)
    XCTAssertEqual(Double(ratio.y), 482.0 * 3.0 / 2532.0, accuracy: 1e-9)
  }

  // MARK: Not-yet-implemented families still throw (touch works; the rest land later)

  func testUnimplementedPrimitivesThrow() async {
    let connection = xpc_connection_create("com.facebook.fbsimulatorcontrol.test.dtuhid", nil)
    xpc_connection_set_event_handler(connection) { _ in }
    xpc_connection_resume(connection)
    let transport = FBSimulatorDTUHIDTransport(
      connection: connection, mainScreenSize: CGSize(width: 100, height: 200), mainScreenScale: 2.0)
    defer { transport.disconnect() }

    // Apple Pay has no single HID usage (it is a double side-button press), so it stays unimplemented.
    await assertThrowsNotImplemented { try await transport.sendButton(direction: .down, button: .applePay) }
  }

  // MARK: Two-finger encoding

  func testDigitizerEventWithTwoFingers() throws {
    let event = try encodeDigitizer(
      IndigoDigitizerEvent(
        pointOne: DigitizerPoint(x: 0.25, y: 0.5),
        pointTwo: DigitizerPoint(x: 0.75, y: 0.5),
        eventType: .start))
    let payload = xpc_dictionary_get_dictionary(event, "payload")!
    let pointOne = xpc_dictionary_get_dictionary(payload, "pointOne")!
    let pointTwo = xpc_dictionary_get_dictionary(payload, "pointTwo")
    XCTAssertNotNil(pointTwo, "a two-finger event must carry pointTwo")
    XCTAssertEqual(xpc_dictionary_get_double(pointOne, "x"), 0.25, accuracy: 1e-9)
    XCTAssertEqual(xpc_dictionary_get_double(pointTwo!, "x"), 0.75, accuracy: 1e-9)
    XCTAssertEqual(xpc_dictionary_get_double(pointTwo!, "y"), 0.5, accuracy: 1e-9)

    // A single-finger event still omits pointTwo.
    let single = try encodeDigitizer(
      IndigoDigitizerEvent(pointOne: DigitizerPoint(x: 0.1, y: 0.2), eventType: .start))
    XCTAssertNil(xpc_dictionary_get_dictionary(xpc_dictionary_get_dictionary(single, "payload")!, "pointTwo"))
  }

  // MARK: Button encoding

  func testButtonUsageMapping() {
    XCTAssertEqual(FBSimulatorHIDButton.homeButton.dtuhidUsage?.page, 0x0C)
    XCTAssertEqual(FBSimulatorHIDButton.homeButton.dtuhidUsage?.code, 0x40)
    XCTAssertEqual(FBSimulatorHIDButton.lock.dtuhidUsage?.code, 0x30)
    XCTAssertEqual(FBSimulatorHIDButton.sideButton.dtuhidUsage?.code, 0x30)
    XCTAssertEqual(FBSimulatorHIDButton.siri.dtuhidUsage?.code, 0xCF)
    XCTAssertNil(FBSimulatorHIDButton.applePay.dtuhidUsage)
  }

  func testButtonEventEnvelope() throws {
    let down = try encodeButton(IndigoButtonEvent(usagePage: 0x0C, usageCode: 0x40, state: .down))
    XCTAssertEqual(xpc_get_type(down), XPC_TYPE_DICTIONARY)
    XCTAssertEqual(messageString(down, "messageType"), "IndigoButtonEvent")
    XCTAssertEqual(messageString(down, "featureIdentifier"), FBSimulatorDTUHIDTransport.digitizerServiceName)

    let payload = xpc_dictionary_get_dictionary(down, "payload")!
    for key in ["usagePage", "usageCode", "state"] {
      XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(payload, key)!), XPC_TYPE_UINT64, "\(key) must be uint64")
    }
    XCTAssertEqual(xpc_dictionary_get_uint64(payload, "usagePage"), 0x0C)
    XCTAssertEqual(xpc_dictionary_get_uint64(payload, "usageCode"), 0x40)
    XCTAssertEqual(xpc_dictionary_get_uint64(payload, "state"), 1) // down
  }

  // MARK: Send pipeline (envelope shape, no connection needed)

  /// The transport's `encode` wraps any `Encodable` payload in the shared `DTUHIDMessage` envelope —
  /// `messageType` discriminator, `isBarrier` bool, the digitizer `featureIdentifier`, and the typed
  /// `payload`. Every capability rides this shape, so it is pinned here independent of any one model.
  func testEncodeWrapsPayloadInEnvelope() throws {
    struct Probe: Encodable {
      let value: UInt64
    }
    let connection = xpc_connection_create("com.facebook.fbsimulatorcontrol.test.dtuhid", nil)
    xpc_connection_set_event_handler(connection) { _ in }
    xpc_connection_resume(connection)
    let transport = FBSimulatorDTUHIDTransport(
      connection: connection, mainScreenSize: CGSize(width: 100, height: 200), mainScreenScale: 2.0)
    defer { transport.disconnect() }

    let message = try transport.encode(messageType: "Probe", payload: Probe(value: 7))

    XCTAssertEqual(xpc_get_type(message), XPC_TYPE_DICTIONARY)
    XCTAssertEqual(messageString(message, "messageType"), "Probe")
    XCTAssertEqual(messageString(message, "featureIdentifier"), FBSimulatorDTUHIDTransport.digitizerServiceName)
    XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(message, "isBarrier")!), XPC_TYPE_BOOL)
    XCTAssertFalse(xpc_dictionary_get_bool(message, "isBarrier"))
    let payload = xpc_dictionary_get_dictionary(message, "payload")
    XCTAssertNotNil(payload)
    XCTAssertEqual(xpc_dictionary_get_uint64(payload!, "value"), 7)
  }

  // MARK: Keyboard encoding

  func testKeyboardButtonEventEnvelope() throws {
    let down = try encodeKeyboard(IndigoKeyboardButtonEvent(usageCode: 4, state: .down)) // 'a'
    XCTAssertEqual(xpc_get_type(down), XPC_TYPE_DICTIONARY)
    XCTAssertEqual(messageString(down, "messageType"), "IndigoKeyboardButtonEvent")
    XCTAssertEqual(messageString(down, "featureIdentifier"), FBSimulatorDTUHIDTransport.digitizerServiceName)

    let payload = xpc_dictionary_get_dictionary(down, "payload")!
    XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(payload, "usageCode")!), XPC_TYPE_UINT64)
    XCTAssertEqual(xpc_dictionary_get_uint64(payload, "usageCode"), 4)
    XCTAssertEqual(xpc_get_type(xpc_dictionary_get_value(payload, "state")!), XPC_TYPE_UINT64)
    XCTAssertEqual(xpc_dictionary_get_uint64(payload, "state"), 1) // down

    let up = try encodeKeyboard(IndigoKeyboardButtonEvent(usageCode: 0xE1, state: .up)) // left-shift up
    let upPayload = xpc_dictionary_get_dictionary(up, "payload")!
    XCTAssertEqual(xpc_dictionary_get_uint64(upPayload, "usageCode"), 0xE1)
    XCTAssertEqual(xpc_dictionary_get_uint64(upPayload, "state"), 2) // up
  }

  func testHIDButtonStateRawValues() {
    XCTAssertEqual(HIDButtonState.down.rawValue, 1)
    XCTAssertEqual(HIDButtonState.up.rawValue, 2)
  }

  // MARK: Helpers

  private func encodeDigitizer(_ event: IndigoDigitizerEvent) throws -> xpc_object_t {
    try XPCEncoder().encode(
      DTUHIDMessage(
        messageType: "IndigoDigitizerEvent",
        featureIdentifier: FBSimulatorDTUHIDTransport.digitizerServiceName,
        payload: event))
  }

  private func encodeKeyboard(_ event: IndigoKeyboardButtonEvent) throws -> xpc_object_t {
    try XPCEncoder().encode(
      DTUHIDMessage(
        messageType: "IndigoKeyboardButtonEvent",
        featureIdentifier: FBSimulatorDTUHIDTransport.digitizerServiceName,
        payload: event))
  }

  private func encodeButton(_ event: IndigoButtonEvent) throws -> xpc_object_t {
    try XPCEncoder().encode(
      DTUHIDMessage(
        messageType: "IndigoButtonEvent",
        featureIdentifier: FBSimulatorDTUHIDTransport.digitizerServiceName,
        payload: event))
  }

  private func messageString(_ dictionary: xpc_object_t, _ key: String) -> String? {
    guard let cString = xpc_dictionary_get_string(dictionary, key) else {
      return nil
    }
    return String(cString: cString)
  }

  private func assertThrowsNotImplemented(
    _ block: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line
  ) async {
    do {
      try await block()
      XCTFail("expected notImplementedOnDTUHIDTransport to be thrown", file: file, line: line)
    } catch let error as FBSimulatorHIDError {
      if case .notImplementedOnDTUHIDTransport = error {
        return
      }
      XCTFail("unexpected FBSimulatorHIDError: \(error)", file: file, line: line)
    } catch {
      XCTFail("unexpected error: \(error)", file: file, line: line)
    }
  }
}
