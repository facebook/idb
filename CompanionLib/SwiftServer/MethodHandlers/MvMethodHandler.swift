/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import GRPCCore
import IDBGRPCSwift

struct MvMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_MvRequest, context: ServerContext) async throws -> Idb_MvResponse {
    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: request.container)
    try await commandExecutor.move_paths(request.srcPaths, to_path: request.dstPath, containerType: fileContainer)
    return .init()
  }
}
