/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A simulator hinge angle in degrees: 0 is closed and 180 is flat.
public struct SimulatorHingeAngle: Equatable, Hashable, Sendable {
  public let degrees: Double

  public init(degrees: Double) throws {
    guard degrees.isFinite, (0...180).contains(degrees) else {
      throw HingeError.invalidAngle
    }
    self.degrees = degrees
  }

  func vendorEvent() throws -> IndigoVendorDefinedEvent {
    try .virtualMachineControl(source: "hinge-slider-control", type: "range", value: degrees)
  }
}

private enum HingeError: Error, LocalizedError {
  case invalidAngle

  var errorDescription: String? {
    switch self {
    case .invalidAngle: "Hinge angle must be finite and between 0 and 180 degrees"
    }
  }
}
