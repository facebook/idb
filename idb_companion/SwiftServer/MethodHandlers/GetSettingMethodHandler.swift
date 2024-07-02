/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC
import IDBGRPCSwift

struct GetSettingMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_GetSettingRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_GetSettingResponse {
    switch request.setting {
    case .locale:
      let localeIdentifier = try await BridgeFuture.value(commandExecutor.get_current_locale_identifier())
      return .with {
        $0.value = localeIdentifier as String
      }
    case .any:
      let domain = request.domain.isEmpty ? nil : request.domain
      let value = try await BridgeFuture.value(commandExecutor.get_preference(request.name, domain: domain))
      return .with {
        $0.value = value as String
      }
    case .UNRECOGNIZED:
      throw GRPCStatus(code: .invalidArgument, message: "Unknown setting case")
    }
  }
}
