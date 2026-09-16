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

struct RevokeMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_RevokeRequest, context: ServerContext) async throws -> Idb_RevokeResponse {

    let mapping: [Idb_RevokeRequest.Permission: TargetSettingsService] = [
      .microphone: .microphone,
      .photos: .photos,
      .camera: .camera,
      .contacts: .contacts,
      .url: .url,
      .location: .location,
      .notification: .notification,
    ]

    var services = try Set(
      request.permissions.map { permission -> TargetSettingsService in
        guard let service = mapping[permission] else {
          throw RPCError(code: .invalidArgument, message: "Unrecognized permission \(permission)")
        }
        return service
      }
    )
    if services.contains(.url) {
      services.remove(.url)
      try await commandExecutor.revoke_deeplink(request.scheme, for_application: request.bundleID)
    }

    if !services.isEmpty {
      try await commandExecutor.revoke(services, for_application: request.bundleID)
    }
    return .init()
  }
}
