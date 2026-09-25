/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
import GRPCCore
import IDBGRPCSwift

struct OrientationMethodHandler {
  let commandExecutor: IDBCommandExecutor

  func get() async throws -> Idb_GetOrientationResponse {
    Self.response(try await commandExecutor.get_orientation())
  }

  func set(request: Idb_SetOrientationRequest) async throws -> Idb_SetOrientationResponse {
    try await commandExecutor.set_orientation(Self.orientation(request.orientation), convention: .device)
    return .init()
  }

  static func response(_ orientation: SimulatorDeviceOrientation) -> Idb_GetOrientationResponse {
    .with {
      switch orientation {
      case .unknown: $0.orientation = .unknown
      case .portrait: $0.orientation = .portrait
      case .portraitUpsideDown: $0.orientation = .portraitUpsideDown
      case .landscapeLeft: $0.orientation = .landscapeLeft
      case .landscapeRight: $0.orientation = .landscapeRight
      case .faceUp: $0.orientation = .faceUp
      case .faceDown: $0.orientation = .faceDown
      }
    }
  }

  /// Shared with the HID stream, which carries the same orientation type in a different convention.
  static func orientation(_ value: Idb_HIDEvent.HIDOrientationType) throws -> SimulatorHIDDeviceOrientation {
    switch value {
    case .portrait: return .portrait
    case .portraitUpsideDown: return .portraitUpsideDown
    case .landscapeLeft: return .landscapeLeft
    case .landscapeRight: return .landscapeRight
    case .UNRECOGNIZED: throw RPCError(code: .invalidArgument, message: "Unrecognized orientation type")
    }
  }
}
