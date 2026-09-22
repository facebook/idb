/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import FBSimulatorControl
import GRPCCore
import IDBGRPCSwift
import XCTest

final class OrientationRequestTranslationTests: XCTestCase {
  func testAllReadStatesSurviveTheWire() throws {
    let cases: [(SimulatorDeviceOrientation, Idb_GetOrientationResponse.Orientation)] = [
      (.unknown, .unknown), (.portrait, .portrait), (.portraitUpsideDown, .portraitUpsideDown),
      (.landscapeLeft, .landscapeLeft), (.landscapeRight, .landscapeRight),
      (.faceUp, .faceUp), (.faceDown, .faceDown),
    ]
    for (state, expected) in cases {
      let response = OrientationMethodHandler.response(state)
      let decoded = try Idb_GetOrientationResponse(serializedBytes: response.serializedData())
      XCTAssertEqual(decoded.orientation, expected)
    }
  }

  func testWritesPreservePhysicalDirectionNames() throws {
    let cases: [(Idb_HIDEvent.HIDOrientationType, SimulatorDeviceOrientation)] = [
      (.portrait, .portrait), (.portraitUpsideDown, .portraitUpsideDown),
      (.landscapeLeft, .landscapeLeft), (.landscapeRight, .landscapeRight),
    ]
    for (input, expected) in cases {
      XCTAssertEqual(try OrientationMethodHandler.orientation(input), expected)
    }
    XCTAssertThrowsError(try OrientationMethodHandler.orientation(.UNRECOGNIZED(99))) { error in
      XCTAssertEqual((error as? RPCError)?.code, .invalidArgument)
    }
  }
}
