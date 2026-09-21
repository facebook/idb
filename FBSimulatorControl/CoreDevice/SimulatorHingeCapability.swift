/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XPC

enum SimulatorHingeCapability {
  static func requireSupported(on simulator: Simulator) async throws {
    let request = try SimulatorCoreDevice.request(
      action: "com.apple.coredevice.action.querymotioncapabilities", deviceID: simulator.udid,
      version: SimulatorCoreDevice.installedVersion(), input: SimulatorCoreDevice.dictionary([:]))
    let queue = DispatchQueue(label: "com.facebook.FBSimulatorControl.hinge-capability")
    let transport = try SimulatorCoreDeviceXPCTransport(
      simulator: simulator, service: "com.apple.coredevice.feature.monitormotion", queue: queue)
    try await SimulatorCoreDeviceRequest<Void>(transport: transport, queue: queue)
      .read(request, decode: requireSupported(in:))
  }

  static func requireSupported(in reply: xpc_object_t) throws {
    guard xpc_get_type(reply) == XPC_TYPE_DICTIONARY else {
      throw SimulatorCoreDeviceError.unavailable("Invalid motion capabilities reply")
    }
    if let error = xpc_dictionary_get_value(reply, "CoreDevice.error") {
      guard xpc_get_type(error) == XPC_TYPE_DICTIONARY,
        let domain = xpc_dictionary_get_value(error, "domain"), xpc_get_type(domain) == XPC_TYPE_STRING,
        let domainString = xpc_string_get_string_ptr(domain),
        let code = xpc_dictionary_get_value(error, "code"), xpc_get_type(code) == XPC_TYPE_INT64
      else { throw SimulatorCoreDeviceError.unavailable("Invalid motion capabilities error") }
      throw SimulatorCoreDeviceError.unavailable("\(String(cString: domainString)) (\(xpc_int64_get_value(code)))")
    }
    guard let output = xpc_dictionary_get_value(reply, "CoreDevice.output"), xpc_get_type(output) == XPC_TYPE_DICTIONARY,
      let hinge = xpc_dictionary_get_value(output, "hingeAngle"), xpc_get_type(hinge) == XPC_TYPE_BOOL
    else { throw SimulatorCoreDeviceError.unavailable("Missing or invalid hinge angle capability") }
    guard xpc_bool_get_value(hinge) else { throw SimulatorCoreDeviceError.unsupported("Hinge angle") }
  }
}
