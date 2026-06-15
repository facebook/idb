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

  // MARK: Every primitive throws until its capability lands (no silent Indigo fallback)

  /// At the wiring commit the transport is selectable but implements nothing — every primitive must
  /// throw `notImplementedOnDTUHIDTransport`. Following commits flip these to real sends one family
  /// at a time.
  func testAllPrimitivesThrowNotImplemented() async {
    let connection = xpc_connection_create("com.facebook.fbsimulatorcontrol.test.dtuhid", nil)
    xpc_connection_set_event_handler(connection) { _ in }
    xpc_connection_resume(connection)
    let transport = FBSimulatorDTUHIDTransport(connection: connection)
    defer { transport.disconnect() }

    await assertThrowsNotImplemented { try await transport.sendTouch(direction: .down, x: 1, y: 2) }
    await assertThrowsNotImplemented { try await transport.sendKeyboard(direction: .down, keyCode: 4) }
    await assertThrowsNotImplemented { try await transport.sendButton(direction: .down, button: .homeButton) }
    await assertThrowsNotImplemented {
      try await transport.sendTwoFingerTouch(direction: .down, finger1: .zero, finger2: .zero)
    }
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
    let transport = FBSimulatorDTUHIDTransport(connection: connection)
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

  // MARK: Helpers

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
