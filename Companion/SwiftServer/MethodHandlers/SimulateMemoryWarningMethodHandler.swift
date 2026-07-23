/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import GRPC
import IDBGRPCSwift

struct SimulateMemoryWarningMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_SimulateMemoryWarningRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_SimulateMemoryWarningResponse {
    try await commandExecutor.simulateMemoryWarning()
    return .init()
  }
}
