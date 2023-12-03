/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC
import IDBGRPCSwift

struct OpenUrlMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_OpenUrlRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_OpenUrlRequest {
    try await BridgeFuture.await(commandExecutor.open_url(request.url))
    return .init()
  }
}
