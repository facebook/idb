/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC
import IDBGRPCSwift

struct CrashDeleteMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_CrashLogQuery, context: GRPCAsyncServerCallContext) async throws -> Idb_CrashLogResponse {
    let predicate = CrashLogQueryValueTransformer.predicate(from: request)
    let crashes: [FBCrashLogInfo] = try await BridgeFuture.value(commandExecutor.crash_delete(predicate))
    return .with {
      $0.list = crashes.map(CrashLogInfoValueTransformer.responseCrashLogInfo(from:))
    }
  }
}
