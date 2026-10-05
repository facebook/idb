/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class SimulatorFailureKindTests: XCTestCase {

  func testMissingCapabilitiesAreUnsupported() {
    XCTAssertEqual(SimulatorFailureKind(SimulatorDisplayInteractionError.unsupportedCapability("hinge")), .unsupported(capability: "hinge"))
    XCTAssertEqual(SimulatorFailureKind(SimulatorCoreDeviceError.unsupported("display switching")), .unsupported(capability: "display switching"))
  }

  func testStatesALaterAttemptMayFindChangedAreNotReady() {
    let errors: [any Error] = [
      SimulatorCoreDeviceError.unavailable("not booted"), SimulatorCoreDeviceError.timedOut,
      SimulatorDisplayError.changed, SimulatorDisplayError.transitioning, SimulatorDisplayError.noActiveIntegratedDisplay,
      SimulatorDisplayError.ambiguousActiveDisplays(["cover", "inner"]), SimulatorDisplayError.screensNotReported(within: 5),
    ]
    for error in errors {
      XCTAssertEqual(SimulatorFailureKind(error), .notReady, "\(error)")
    }
  }

  func testFailedAttemptsAndWrongRequestsAreFailed() throws {
    let errors: [any Error] = [
      SimulatorCoreDeviceError.malformed("reply"), SimulatorDisplayInteractionError.inactiveDisplay("inner"),
      SimulatorDisplayInteractionError.missingMapping("inner"), SimulatorDisplayInteractionError.invalidPoint(.zero, bounds: .zero),
      SimulatorDisplayInteractionError.nonFinitePoint(.zero),
      SimulatorPoseConfirmationError.notReached(target: .hinge(try SimulatorHingeAngle(degrees: 180)), last: .hinge(try SimulatorHingeAngle(degrees: 90))),
      SimulatorOrientationError.unwritable(.faceUp), NSError(domain: "unsupportedCapability", code: 1),
    ]
    for error in errors {
      XCTAssertEqual(SimulatorFailureKind(error), .failed, "\(error)")
    }
  }

  func testAnUnsupportedCaseWithNoDetailIsFailed() {
    XCTAssertEqual(SimulatorFailureKind(SimulatorCoreDeviceError.unsupported("")), .failed)
  }
}
