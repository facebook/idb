/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import Testing

/// Which orientation and hinge backend a simulator's advertised motion capabilities select.
@Suite
struct SimulatorMotionBackendTests {

  private func capabilities(deviceMotionState: Bool?, hingeAngle: Bool? = nil) -> MotionCapabilities {
    MotionCapabilities(hingeAngle: hingeAngle, deviceMotionState: deviceMotionState)
  }

  @Test
  func advertisedDeviceMotionSelectsTheVendorAndGuestBackends() {
    let advertised = capabilities(deviceMotionState: true)
    #expect(advertised.orientationWriteBackend == .vendorHID)
    #expect(advertised.orientationReadBackend == .guestMotionState)
  }

  @Test
  func absentOrFalseDeviceMotionSelectsTheLegacyBackends() {
    for capabilities in [capabilities(deviceMotionState: false), capabilities(deviceMotionState: nil), .none] {
      #expect(capabilities.orientationWriteBackend == .purple)
      #expect(capabilities.orientationReadBackend == .legacyService)
    }
  }

  @Test
  func hingeIsRequiredIndependentlyOfDeviceMotion() throws {
    try capabilities(deviceMotionState: false, hingeAngle: true).require(.hingeAngle)
    for capabilities in [capabilities(deviceMotionState: true, hingeAngle: false), capabilities(deviceMotionState: true), .none] {
      let error = #expect(throws: (any Error).self) { try capabilities.require(.hingeAngle) }
      guard let error else { continue }
      guard case let SimulatorCoreDeviceError.unsupported(detail) = error else {
        Issue.record("\(error)")
        continue
      }
      #expect(detail == "Hinge angle, supported only on iPhone Duo simulators")
    }
  }

  @Test
  func aRuntimeThatCannotAnswerTheQueryAdvertisesNothing() async throws {
    let none = try await MotionCapabilities.resolve { throw SimulatorCoreDeviceError.unsupported("com.apple.coredevice.feature.monitormotion") }
    #expect(none == .none)
    #expect(none.orientationWriteBackend == .purple)
  }

  @Test
  func anOperationalFailureOfTheQueryIsNotAFallback() async {
    for error: SimulatorCoreDeviceError in [.unavailable("closed"), .malformed("CoreDevice.output.hingeAngle"), .timedOut] {
      do {
        _ = try await MotionCapabilities.resolve { throw error }
        Issue.record("Expected \(error) to surface")
      } catch let surfaced as SimulatorCoreDeviceError {
        #expect(surfaced.localizedDescription == error.localizedDescription)
      } catch {
        Issue.record("\(error)")
      }
    }
  }

  @Test
  func anAnsweredQueryPassesThrough() async throws {
    let answered = try await MotionCapabilities.resolve { self.capabilities(deviceMotionState: true, hingeAngle: true) }
    #expect(answered == capabilities(deviceMotionState: true, hingeAngle: true))
  }
}
