/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC
import IDBGRPCSwift

struct CrashShowMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_CrashShowRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_CrashShowResponse {
    guard !request.name.isEmpty else {
      throw GRPCStatus(code: .invalidArgument, message: "Missing crash name")
    }

    let predicate = FBCrashLogInfo.predicate(forName: request.name)
    let crash = try await BridgeFuture.value(commandExecutor.crash_show(predicate))
    return .with {
      $0.info = CrashLogInfoValueTransformer.responseCrashLogInfo(from: crash.info)
      $0.contents = crash.contents
    }
  }
}
