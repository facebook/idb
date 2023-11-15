/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC
import IDBGRPCSwift

struct ListSettingsMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_ListSettingRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_ListSettingResponse {
    switch request.setting {
    case .locale:
      return .with {
        $0.values = commandExecutor.list_locale_identifiers()
      }
    case .any, .UNRECOGNIZED:
      throw GRPCStatus(code: .invalidArgument, message: "Unknown setting case")
    }
  }
}
