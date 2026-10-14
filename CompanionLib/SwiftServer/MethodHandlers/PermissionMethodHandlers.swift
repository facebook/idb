/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import GRPCCore
import IDBGRPCSwift

struct ApproveMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_ApproveRequest, context: ServerContext) async throws -> Idb_ApproveResponse {

    let mapping: [Idb_ApproveRequest.Permission: TargetSettingsService] = [
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
      try await commandExecutor.approveDeeplink(request.scheme, forApplication: request.bundleID)
    }

    if !services.isEmpty {
      try await commandExecutor.approve(services, forApplication: request.bundleID)
    }
    return .init()
  }
}

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
      try await commandExecutor.revokeDeeplink(request.scheme, forApplication: request.bundleID)
    }

    if !services.isEmpty {
      try await commandExecutor.revoke(services, forApplication: request.bundleID)
    }
    return .init()
  }
}
