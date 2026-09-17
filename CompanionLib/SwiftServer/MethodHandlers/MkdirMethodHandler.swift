/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import GRPCCore
import IDBGRPCSwift

struct MkdirMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_MkdirRequest, context: ServerContext) async throws -> Idb_MkdirResponse {
    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: request.container)
    try await commandExecutor.create_directory(request.path, containerType: fileContainer)
    return .init()
  }
}
