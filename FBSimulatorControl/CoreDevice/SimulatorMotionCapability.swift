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

  let hingeAngle: Bool?
  let deviceMotionState: Bool?
  let spatialOrientation: Bool?

  static func query(on simulator: Simulator) async throws -> MotionCapabilities {
    try await simulator.coreDevice.perform(action: action, service: service, input: CoreDeviceEmptyInput(), as: MotionCapabilities.self)
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

  func requireSupported(on simulator: Simulator) async throws {
    try await MotionCapabilities.query(on: simulator).require(self)
  }

  func requireSupported(in reply: xpc_object_t) throws {
    try CoreDeviceReply.decode(MotionCapabilities.self, from: reply).require(self)
  }
}
