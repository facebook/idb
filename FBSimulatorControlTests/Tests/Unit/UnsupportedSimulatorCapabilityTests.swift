/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class UnsupportedSimulatorCapabilityTests: XCTestCase {

  func testOnlyPermanentCasesAreClassified() {
    XCTAssertEqual(
      unsupportedSimulatorCapability(in: SimulatorDisplayInteractionError.unsupportedCapability("hinge")),
      "hinge"
    )
    XCTAssertEqual(
      unsupportedSimulatorCapability(in: SimulatorCoreDeviceError.unsupported("display switching")),
      "display switching"
    )
    // Each of these is a failed attempt or a wrong request. Reading one as a permanent absence
    // retires a device that would have answered the very next call.
    XCTAssertNil(unsupportedSimulatorCapability(in: SimulatorDisplayInteractionError.inactiveDisplay("inner")))
    XCTAssertNil(unsupportedSimulatorCapability(in: SimulatorDisplayInteractionError.missingMapping("inner")))
    XCTAssertNil(
      unsupportedSimulatorCapability(
        in: SimulatorDisplayInteractionError.invalidPoint(.zero, bounds: .zero)))
    XCTAssertNil(
      unsupportedSimulatorCapability(
        in: SimulatorDisplayInteractionError.nonFinitePoint(.zero)))
    XCTAssertNil(unsupportedSimulatorCapability(in: SimulatorCoreDeviceError.unavailable("not booted")))
  }

  func testAnErrorOfAnotherKindIsNotClassified() {
    struct Transient: Error {}
    XCTAssertNil(unsupportedSimulatorCapability(in: Transient()))
    XCTAssertNil(
      unsupportedSimulatorCapability(in: NSError(domain: "unsupportedCapability", code: 1)))
  }

  func testAPermanentCaseWithNoDetailIsNotClassified() {
    XCTAssertNil(unsupportedSimulatorCapability(in: SimulatorDisplayInteractionError.unsupportedCapability("")))
    XCTAssertNil(unsupportedSimulatorCapability(in: SimulatorCoreDeviceError.unsupported("")))
  }
}
