/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import IOKit

/// A simulator hinge angle in degrees: 0 is closed and 180 is flat.
public struct SimulatorHingeAngle: Equatable, Hashable, Sendable {
  public let degrees: Double

  public init(degrees: Double) throws {
    guard degrees.isFinite, (0...180).contains(degrees) else {
      throw HingeError.invalidAngle
    }
    self.degrees = degrees
  }

  static func requireSupportedModel(_ model: String?) throws {
    // The device profile does not advertise a hinge feature; this is the demonstrated model.
    guard model == "iPhone19,4" else { throw HingeError.unsupportedModel }
  }

  func vendorEvent() throws -> IndigoVendorDefinedEvent {
    let payload: [String: Any] = [
      "provider": "com.apple.Virtualization.VirtualMachines",
      "source": "hinge-slider-control",
      "type": "range",
      "value": degrees,
    ]
    guard let serialized = IOCFSerialize(payload as CFDictionary, 1) else {
      throw HingeError.serializationFailed
    }
    return IndigoVendorDefinedEvent(usagePage: 0xff61, usage: 0x5b, version: 0, data: serialized as Data)
  }
}

private enum HingeError: Error, LocalizedError {
  case invalidAngle
  case unsupportedModel
  case serializationFailed

  var errorDescription: String? {
    switch self {
    case .invalidAngle: "Hinge angle must be finite and between 0 and 180 degrees"
    case .unsupportedModel: "Hinge input is supported only on iPhone Duo simulators"
    case .serializationFailed: "Could not serialize the simulator hinge input"
    }
  }
}

struct IndigoVendorDefinedEvent: Encodable {
  let usagePage: UInt16
  let usage: UInt16
  let version: UInt32
  let data: Data
}
