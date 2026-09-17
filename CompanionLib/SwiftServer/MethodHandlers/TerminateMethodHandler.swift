/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import GRPCCore
import IDBGRPCSwift

struct TerminateMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_TerminateRequest, context: ServerContext) async throws -> Idb_TerminateResponse {
    try await commandExecutor.kill_application(request.bundleID)
    return .init()
  }
}
