/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import GRPCCore
import IDBGRPCSwift

struct UninstallMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_UninstallRequest, context: ServerContext) async throws -> Idb_UninstallResponse {
    try await commandExecutor.uninstall_application(request.bundleID)
    return .init()
  }
}
