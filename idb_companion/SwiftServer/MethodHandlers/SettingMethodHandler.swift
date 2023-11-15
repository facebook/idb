/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC
import IDBGRPCSwift

struct SettingMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_SettingRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_SettingResponse {
    switch request.setting {
    case let .hardwareKeyboard(hardwareKeyboard):
      try await BridgeFuture.await(commandExecutor.set_hardware_keyboard_enabled(hardwareKeyboard.enabled))

    case let .stringSetting(stringSetting):
      switch stringSetting.setting {
      case .locale:
        try await BridgeFuture.await(commandExecutor.set_locale_with_identifier(stringSetting.value))

      case .any:
        let domain = stringSetting.domain.isEmpty ? nil : stringSetting.domain
        let type = stringSetting.valueType.isEmpty ? nil : stringSetting.valueType
        try await BridgeFuture.await(commandExecutor.set_preference(stringSetting.name, value: stringSetting.value, type: type, domain: domain))

      case .UNRECOGNIZED:
        throw GRPCStatus(code: .invalidArgument, message: "Unknown setting case")
      }
    case .none:
      throw GRPCStatus(code: .invalidArgument, message: "Unknown setting case")
    }

    return .init()
  }
}
