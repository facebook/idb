/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBSimulatorControl
import GRPCCore
import IDBGRPCSwift

struct FocusMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_FocusRequest, context: ServerContext) async throws -> Idb_FocusResponse {
    try await commandExecutor.focus()
    return .init()
  }
}

struct OpenUrlMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_OpenUrlRequest, context: ServerContext) async throws -> Idb_OpenUrlRequest {
    try await commandExecutor.open_url(request.url)
    return .init()
  }
}

struct SetLocationMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_SetLocationRequest, context: ServerContext) async throws -> Idb_SetLocationResponse {
    try await commandExecutor.set_location(request.location.latitude, longitude: request.location.longitude)
    return .init()
  }
}

struct SimulateMemoryWarningMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_SimulateMemoryWarningRequest, context: ServerContext) async throws -> Idb_SimulateMemoryWarningResponse {
    try await commandExecutor.simulateMemoryWarning()
    return .init()
  }
}

struct HingeAngleMethodHandler {
  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_HingeAngleRequest, context: ServerContext) async throws -> Idb_HingeAngleResponse {
    let angle = try await commandExecutor.hinge_angle()
    return .with { $0.angle = angle }
  }
}

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
