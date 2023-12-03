/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC
import IDBGRPCSwift

struct MkdirMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_MkdirRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_MkdirResponse {
    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: request.container)
    try await BridgeFuture.await(commandExecutor.create_directory(request.path, containerType: fileContainer))
    return .init()
  }
}
