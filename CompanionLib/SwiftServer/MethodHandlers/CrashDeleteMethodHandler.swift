/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import GRPCCore
import IDBGRPCSwift

struct CrashDeleteMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_CrashLogQuery, context: ServerContext) async throws -> Idb_CrashLogResponse {
    let predicate = CrashLogQueryValueTransformer.predicate(from: request)
    let crashes = try await commandExecutor.crash_delete(predicate)
    return .with {
      $0.list = crashes.map(CrashLogInfoValueTransformer.responseCrashLogInfo(from:))
    }
  }
}
