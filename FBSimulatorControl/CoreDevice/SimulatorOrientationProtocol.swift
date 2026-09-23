/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XPC

/// The orientation service older runtimes vend, which speaks the `dtuhidd` message envelope.
enum SimulatorOrientationProtocol {
  static let service = "com.apple.coredevice.feature.remote.devicecontrol.orientation"

  private enum Request: Encodable {
    case currentOrientation
  }

  struct Reply: Decodable {
    let currentDeviceOrientation: SimulatorDeviceOrientation
  }

  static func read(on simulator: Simulator) async throws -> SimulatorDeviceOrientation {
    try await simulator.coreDevice.send(service: service, message: request(), decode: orientation)
  }

  static func request() throws -> xpc_object_t {
    try XPCEncoder().encode(DTUHIDMessage(messageType: "OrientationRequest", featureIdentifier: service, payload: Request.currentOrientation))
  }

  static func orientation(_ reply: xpc_object_t) throws -> SimulatorDeviceOrientation {
    try SimulatorCoreDevice.decode(Reply.self, from: reply).currentDeviceOrientation
  }
}
