/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBSimulatorControl
import Foundation
import GRPC
import IDBGRPCSwift

struct XCTestListTestsMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_XctestListTestsRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_XctestListTestsResponse {
    let tests: [String] = try await BridgeFuture.value(
      commandExecutor.list_tests_(in_bundle: request.bundleName, with_app: request.appPath)
    )
    return .with {
      $0.names = tests
    }
  }
}
