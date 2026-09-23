/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XPC

enum SimulatorMotionCapability: String {
  case hingeAngle
  case deviceMotionState

  private var name: String {
    switch self {
    case .hingeAngle: "Hinge angle"
    case .deviceMotionState: "Device motion state"
    }
  }

  static let service = "com.apple.coredevice.feature.monitormotion"
  static let action = "com.apple.coredevice.action.querymotioncapabilities"

  func requireSupported(on simulator: Simulator) async throws {
    try await simulator.coreDevice.perform(
      action: Self.action, service: Self.service, input: CoreDeviceEmptyInput(), decode: requireSupported(in:))
  }

  func requireSupported(in reply: xpc_object_t) throws {
    let output = try CoreDeviceReply.output(of: reply)
    guard let capability = xpc_dictionary_get_value(output, rawValue) else {
      throw SimulatorCoreDeviceError.unsupported(name)
    }
    guard xpc_get_type(capability) == XPC_TYPE_BOOL else {
      throw SimulatorCoreDeviceError.unavailable("Invalid \(name) capability")
    }
    guard xpc_bool_get_value(capability) else { throw SimulatorCoreDeviceError.unsupported(name) }
  }
}
