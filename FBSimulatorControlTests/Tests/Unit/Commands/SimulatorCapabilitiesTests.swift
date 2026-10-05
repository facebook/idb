/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import XCTest

final class SimulatorCapabilitiesTests: XCTestCase {

  private func display(_ id: String, integrated: Bool = true) -> SimulatorDisplay {
    SimulatorDisplay(
      uniqueID: id, name: id, activity: .active, isPrimary: false, isIntegrated: integrated,
      bounds: CGRect(x: 0, y: 0, width: 1200, height: 800), scale: 2, rotation: .upright)
  }

  private func configuration(_ displays: [SimulatorDisplay]) -> SimulatorDisplayConfiguration {
    SimulatorDisplayConfiguration(generation: 1, displays: displays, active: displays.first.map { .identified($0) } ?? .unresolved, phase: .settled)
  }

  func testAnIPhoneDuoHasEveryCapability() throws {
    let capabilities = try SimulatorCapabilities(
      motion: MotionCapabilities(hingeAngle: true, deviceMotionState: true), displays: .success(configuration([display("cover"), display("inner")])))
    XCTAssertEqual(capabilities, SimulatorCapabilities(hingeAngle: true, deviceMotion: true, multipleDisplays: true))
  }

  func testOnlyIntegratedDisplaysCount() throws {
    let capabilities = try SimulatorCapabilities(motion: .none, displays: .success(configuration([display("lcd"), display("tv", integrated: false)])))
    XCTAssertEqual(capabilities, SimulatorCapabilities(hingeAngle: false, deviceMotion: false, multipleDisplays: false))
  }

  func testARuntimeWithoutDisplayReportsHasOneDisplay() throws {
    let capabilities = try SimulatorCapabilities(
      motion: MotionCapabilities(hingeAngle: nil, deviceMotionState: true), displays: .failure(SimulatorCoreDeviceError.unsupported("display info")))
    XCTAssertEqual(capabilities, SimulatorCapabilities(hingeAngle: false, deviceMotion: true, multipleDisplays: false))
  }

  func testAServiceThatIsNotReadyIsThrown() {
    XCTAssertThrowsError(try SimulatorCapabilities(motion: .none, displays: .failure(SimulatorCoreDeviceError.timedOut))) {
      XCTAssertEqual(SimulatorFailureKind($0), .notReady)
    }
  }
}
