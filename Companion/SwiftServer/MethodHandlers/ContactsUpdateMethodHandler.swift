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

struct ContactsUpdateMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_ContactsUpdateRequest, context: ServerContext) async throws -> Idb_ContactsUpdateResponse {
    try await commandExecutor.update_contacts(request.payload.data)
    return .init()
  }
}
