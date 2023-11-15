/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC
import IDBGRPCSwift

struct UninstallMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_UninstallRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_UninstallResponse {
    try await BridgeFuture.await(commandExecutor.uninstall_application(request.bundleID))
    return .init()
  }
}
