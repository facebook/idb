/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC
import IDBGRPCSwift

struct ClearKeychainMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_ClearKeychainRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ClearKeychainResponse {
    try await BridgeFuture.await(commandExecutor.clear_keychain())
    return .init()
  }
}
