/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import GRPCCore
import IDBGRPCSwift

struct CrashListMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_CrashLogQuery, context: ServerContext) async throws -> Idb_CrashLogResponse {
    let predicate = CrashLogQueryTranslation.predicate(from: request)
    let crashes = try await commandExecutor.crash_list(predicate)
    return Idb_CrashLogResponse.with {
      $0.list = crashes.map(CrashLogInfoTranslation.responseCrashLogInfo(from:))
    }
  }
}

struct CrashShowMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_CrashShowRequest, context: ServerContext) async throws -> Idb_CrashShowResponse {
    guard !request.name.isEmpty else {
      throw RPCError(code: .invalidArgument, message: "Missing crash name")
    }

    let predicate = CrashLogPredicate.name(request.name)
    let crash = try await commandExecutor.crash_show(predicate)
    return .with {
      $0.info = CrashLogInfoTranslation.responseCrashLogInfo(from: crash.info)
      $0.contents = crash.contents
    }
  }
}

struct CrashDeleteMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_CrashLogQuery, context: ServerContext) async throws -> Idb_CrashLogResponse {
    let predicate = CrashLogQueryTranslation.predicate(from: request)
    let crashes = try await commandExecutor.crash_delete(predicate)
    return .with {
      $0.list = crashes.map(CrashLogInfoTranslation.responseCrashLogInfo(from:))
    }
  }
}
