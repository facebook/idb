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

struct GetSettingMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_GetSettingRequest, context: ServerContext) async throws -> Idb_GetSettingResponse {
    switch request.setting {
    case .locale:
      let localeIdentifier = try await commandExecutor.get_current_locale_identifier()
      return .with {
        $0.value = localeIdentifier
      }
    case .any:
      let domain = request.domain.isEmpty ? nil : request.domain
      let value = try await commandExecutor.get_preference(request.name, domain: domain)
      return .with {
        $0.value = value
      }
    case .UNRECOGNIZED:
      throw RPCError(code: .invalidArgument, message: "Unknown setting case")
    }
  }
}
