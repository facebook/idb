/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC
import IDBGRPCSwift

struct SetLocationMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_SetLocationRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_SetLocationResponse {
    try await BridgeFuture.await(commandExecutor.set_location(request.location.latitude, longitude: request.location.longitude))
    return .init()
  }
}
