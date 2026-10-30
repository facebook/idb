/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import Testing

/// The crown transport, against a synthetic scroll service that answers the liveness barrier.
@Suite
struct SimulatorCrownHIDTransportTests {

  // MARK: - The rotation a caller can express

  @Test(arguments: [Double.nan, .infinity, -.infinity])
  func aNonFiniteDeltaIsRejected(_ delta: Double) throws {
    #expect {
      try SimulatorCrownRotation(delta: delta)
    } throws: { error in
      guard case .notFinite = error as? SimulatorCrownRotationError else { return false }
      return true
    }
  }

  @Test
  func aZeroDeltaIsRejected() throws {
    #expect {
      try SimulatorCrownRotation(delta: 0)
    } throws: { error in
      guard case .zero = error as? SimulatorCrownRotationError else { return false }
      return true
    }
  }

  @Test(arguments: [1800.000_001, -1800.000_001, 1e9])
  func aDeltaBeyondTheBoundIsRejected(_ delta: Double) throws {
    #expect {
      try SimulatorCrownRotation(delta: delta)
    } throws: { error in
      guard case let .outOfRange(rejected, maximum) = error as? SimulatorCrownRotationError else { return false }
      return rejected == delta && maximum == 1800
    }
  }

  @Test(arguments: [0.5, -0.5, 1800.0, -1800.0])
  func theBoundsThemselvesAreAccepted(_ delta: Double) {
    #expect(throws: Never.self) {
      try SimulatorCrownRotation(delta: delta)
    }
  }

  /// A large rotation stays bounded on the wire, and the steps keep the caller's sign and total.
  @Test
  func theStepsAreBoundedAndKeepTheSignAndTotal() throws {
    let rotation = try SimulatorCrownRotation(delta: -1800)
    let steps = rotation.steps
    #expect(steps.count == 256)
    #expect(steps.allSatisfy { $0 < 0 })
    #expect(abs(steps.reduce(0, +) - rotation.delta) < 1e-9)
  }

  @Test
  func aSmallRotationIsStillSentAsAtLeastOneStep() throws {
    #expect(try SimulatorCrownRotation(delta: 0.5).steps == [0.5])
  }
}
