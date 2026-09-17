/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import GRPCCore
import IDBGRPCSwift

struct RmMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_RmRequest, context: ServerContext) async throws -> Idb_RmResponse {
    let fileContainer = FileContainerValueTransformer.rawFileContainer(from: request.container)
    try await commandExecutor.remove_paths(request.paths, containerType: fileContainer)
    return .init()
  }
}
