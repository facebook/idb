/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC
import IDBGRPCSwift

struct TerminateMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_TerminateRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_TerminateResponse {
    try await BridgeFuture.await(commandExecutor.kill_application(request.bundleID))
    return .init()
  }
}
