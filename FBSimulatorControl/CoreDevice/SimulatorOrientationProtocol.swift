/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XPC

enum SimulatorOrientationProtocol {
  static let service = "com.apple.coredevice.feature.remote.devicecontrol.orientation"

  private enum Request: Encodable {
    case currentOrientation
  }

  static func read(on simulator: Simulator) async throws -> SimulatorDeviceOrientation {
    let message = try request()
    let queue = DispatchQueue(label: "com.facebook.FBSimulatorControl.orientation")
    let transport = try SimulatorCoreDeviceXPCTransport(simulator: simulator, service: service, queue: queue)
    return try await CoreDeviceSession<SimulatorDeviceOrientation>(transport: transport, queue: queue)
      .read(message, decode: orientation)
  }

  static func request() throws -> xpc_object_t {
    try XPCEncoder().encode(DTUHIDMessage(messageType: "OrientationRequest", featureIdentifier: service, payload: Request.currentOrientation))
  }

  static func orientation(_ reply: xpc_object_t) throws -> SimulatorDeviceOrientation {
    guard xpc_get_type(reply) == XPC_TYPE_DICTIONARY,
      let value = xpc_dictionary_get_value(reply, "currentDeviceOrientation"), xpc_get_type(value) == XPC_TYPE_STRING,
      let string = xpc_string_get_string_ptr(value), let orientation = SimulatorDeviceOrientation(rawValue: String(cString: string))
    else { throw SimulatorCoreDeviceError.unavailable("Missing or invalid currentDeviceOrientation") }
    return orientation
  }
}
