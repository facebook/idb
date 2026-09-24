/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XPC

/// What a simulator's motion provider advertises, as `querymotioncapabilities` reports it. A
/// capability the provider does not mention is not supported, the same as one it reports `false`.
struct MotionCapabilities: Decodable, Equatable, Sendable {
  static let service = "com.apple.coredevice.feature.monitormotion"
  static let action = "com.apple.coredevice.action.querymotioncapabilities"

  /// What a runtime without the motion feature advertises: nothing.
  static let none = MotionCapabilities(hingeAngle: nil, deviceMotionState: nil, spatialOrientation: nil)

  let hingeAngle: Bool?
  let deviceMotionState: Bool?
  let spatialOrientation: Bool?

  /// The capabilities the simulator advertises. A runtime, CoreDevice installation or toolchain
  /// that cannot answer the query at all advertises `none`; an operational failure is an error.
  static func resolve(on simulator: Simulator) async throws -> MotionCapabilities {
    try await resolve {
      try await simulator.coreDevice.perform(action: action, service: service, input: CoreDeviceEmptyInput(), as: MotionCapabilities.self)
    }
  }

  static func resolve(_ query: () async throws -> MotionCapabilities) async throws -> MotionCapabilities {
    do {
      return try await query()
    } catch SimulatorCoreDeviceError.unsupported {
      return .none
    }
  }

  func supports(_ capability: SimulatorMotionCapability) -> Bool {
    switch capability {
    case .hingeAngle: hingeAngle == true
    case .deviceMotionState: deviceMotionState == true
    }
  }

  func require(_ capability: SimulatorMotionCapability) throws {
    guard supports(capability) else { throw SimulatorCoreDeviceError.unsupported(capability.name) }
  }

  /// Orientation writes go through the virtual machine's orientation control where the runtime
  /// reports device motion; the legacy Purple event can leave such a runtime's active display
  /// unchanged. Runtimes without it take Purple.
  var orientationWriteBackend: OrientationWriteBackend {
    supports(.deviceMotionState) ? .vendorHID : .purple
  }

  /// Orientation reads come from the guest's own motion state where the runtime reports device
  /// motion, since the CoreDevice stream can replay a stale snapshot; otherwise from the legacy
  /// orientation service.
  var orientationReadBackend: OrientationReadBackend {
    supports(.deviceMotionState) ? .guestMotionState : .legacyService
  }
}

enum OrientationWriteBackend: Equatable, Sendable {
  case vendorHID
  case purple
}

enum OrientationReadBackend: Equatable, Sendable {
  case guestMotionState
  case legacyService
}

enum SimulatorMotionCapability: String {
  case hingeAngle
  case deviceMotionState

  var name: String {
    switch self {
    case .hingeAngle: "Hinge angle"
    case .deviceMotionState: "Device motion state"
    }
  }
}
