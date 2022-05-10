/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import IDBGRPCSwift
import GRPC

struct FocusMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_FocusRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_FocusResponse {
    try await BridgeFuture.await(commandExecutor.focus())
    return .init()
  }

}
