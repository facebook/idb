/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC
import IDBGRPCSwift

struct MvMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_MvRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_MvResponse {
    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: request.container)
    try await BridgeFuture.await(commandExecutor.move_paths(request.srcPaths, to_path: request.dstPath, containerType: fileContainer))
    return .init()
  }
}
