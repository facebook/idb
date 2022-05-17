/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import IDBGRPCSwift
import GRPC

struct ContactsUpdateMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_ContactsUpdateRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ContactsUpdateResponse {
    try await BridgeFuture.await(commandExecutor.update_contacts(request.payload.data))
    return .init()
  }

}
