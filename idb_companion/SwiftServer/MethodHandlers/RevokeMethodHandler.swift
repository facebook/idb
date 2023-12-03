/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC
import IDBGRPCSwift

struct RevokeMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_RevokeRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_RevokeResponse {

    // Swift implements custom bridging logic for NSNotificationName and this causes ALL string enums ended with "Notification"
    // suffix translates in this special way
    let notificationApprovalService = FBTargetSettingsService.FBTargetSettingsService

    let mapping: [Idb_RevokeRequest.Permission: FBTargetSettingsService] = [
      .microphone: .microphone,
      .photos: .photos,
      .camera: .camera,
      .contacts: .contacts,
      .url: .url,
      .location: .location,
      .notification: notificationApprovalService,
    ]

    var services = try Set(
      request.permissions.map { permission -> FBTargetSettingsService in
        guard let service = mapping[permission] else {
          throw GRPCStatus(code: .invalidArgument, message: "Unrecognized permission \(permission)")
        }
        return service
      }
    )
    if services.contains(.url) {
      services.remove(.url)
      try await BridgeFuture.await(commandExecutor.revoke_deeplink(request.scheme, for_application: request.bundleID))
    }

    if !services.isEmpty {
      try await BridgeFuture.await(commandExecutor.revoke(services, for_application: request.bundleID))
    }
    return .init()
  }
}
