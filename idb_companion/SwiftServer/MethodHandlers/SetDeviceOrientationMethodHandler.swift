/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC
import IDBGRPCSwift
import FBSimulatorControl

struct SetDeviceOrientationMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_SetDeviceOrientationRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_SetDeviceOrientationResponse {
      try await BridgeFuture.await(commandExecutor.set_device_orientation(fbSimulatorDeviceOrientation(from: request.deviceOrientation)))
    return .init()
  }

  private func fbSimulatorDeviceOrientation(from request: Idb_SetDeviceOrientationRequest.DeviceOrientation) throws -> FBSimulatorDeviceOrientation {
    switch request {
    case .portrait:
      return .portrait
    case .portraitUpsideDown:
      return .portraitUpsideDown
    case .landscapeLeft:
      return .landscapeLeft
    case .landscapeRight:
      return .landscapeRight
    default:
      throw GRPCStatus(code: .invalidArgument, message: "Unrecognized deviceOrientation")
    }
  }
}

