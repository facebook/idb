/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

/// Which orientation and hinge backend a simulator's advertised motion capabilities select.
final class SimulatorMotionBackendTests: XCTestCase {

  private func capabilities(deviceMotionState: Bool?, hingeAngle: Bool? = nil) -> MotionCapabilities {
    MotionCapabilities(hingeAngle: hingeAngle, deviceMotionState: deviceMotionState, spatialOrientation: nil)
  }

  func testAdvertisedDeviceMotionSelectsTheVendorAndGuestBackends() {
    let advertised = capabilities(deviceMotionState: true)
    XCTAssertEqual(advertised.orientationWriteBackend, .vendorHID)
    XCTAssertEqual(advertised.orientationReadBackend, .guestMotionState)
  }

  func testAbsentOrFalseDeviceMotionSelectsTheLegacyBackends() {
    for capabilities in [capabilities(deviceMotionState: false), capabilities(deviceMotionState: nil), .none] {
      XCTAssertEqual(capabilities.orientationWriteBackend, .purple)
      XCTAssertEqual(capabilities.orientationReadBackend, .legacyService)
    }
  }

  func testHingeIsRequiredIndependentlyOfDeviceMotion() throws {
    try capabilities(deviceMotionState: false, hingeAngle: true).require(.hingeAngle)
    for capabilities in [capabilities(deviceMotionState: true, hingeAngle: false), capabilities(deviceMotionState: true), .none] {
      XCTAssertThrowsError(try capabilities.require(.hingeAngle)) { error in
        guard case let SimulatorCoreDeviceError.unsupported(detail) = error else { return XCTFail("\(error)") }
        XCTAssertEqual(detail, "Hinge angle")
      }
    }
  }

  func testARuntimeThatCannotAnswerTheQueryAdvertisesNothing() async throws {
    let none = try await MotionCapabilities.resolve { throw SimulatorCoreDeviceError.unsupported("com.apple.coredevice.feature.monitormotion") }
    XCTAssertEqual(none, .none)
    XCTAssertEqual(none.orientationWriteBackend, .purple)
  }

  func testAnOperationalFailureOfTheQueryIsNotAFallback() async {
    for error: SimulatorCoreDeviceError in [.unavailable("closed"), .malformed("CoreDevice.output.hingeAngle"), .timedOut] {
      do {
        _ = try await MotionCapabilities.resolve { throw error }
        XCTFail("Expected \(error) to surface")
      } catch let surfaced as SimulatorCoreDeviceError {
        XCTAssertEqual(surfaced.localizedDescription, error.localizedDescription)
      } catch {
        XCTFail("\(error)")
      }
    }
  }

  func testAnAnsweredQueryPassesThrough() async throws {
    let answered = try await MotionCapabilities.resolve { self.capabilities(deviceMotionState: true, hingeAngle: true) }
    XCTAssertEqual(answered, capabilities(deviceMotionState: true, hingeAngle: true))
  }
}
