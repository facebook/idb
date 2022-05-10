/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import IDBGRPCSwift
import GRPC

struct CrashListMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_CrashLogQuery, context: GRPCAsyncServerCallContext) async throws -> Idb_CrashLogResponse {
    let predicate = CrashLogQueryValueTransformer.predicate(from: request)
    let crashes: [FBCrashLogInfo] = try await BridgeFuture.value(commandExecutor.crash_list(predicate))
    return Idb_CrashLogResponse.with {
      $0.list = crashes.map(Self.responseCrashLogInfo(from:))
    }
  }

  static func responseCrashLogInfo(from crash: FBCrashLogInfo) -> Idb_CrashLogInfo {
    return .with {
      $0.name = crash.name
      $0.processName = crash.processName
      $0.parentProcessName = crash.parentProcessName
      $0.processIdentifier = UInt64(crash.processIdentifier)
      $0.parentProcessIdentifier = UInt64(crash.parentProcessIdentifier)
      $0.timestamp = UInt64(crash.date.timeIntervalSince1970)
    }
  }

}
