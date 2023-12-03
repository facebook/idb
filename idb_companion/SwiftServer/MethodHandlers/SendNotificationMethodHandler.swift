/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import GRPC
import IDBGRPCSwift

struct SendNotificationMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(request: Idb_SendNotificationRequest, context: GRPCAsyncServerCallContext) async throws -> Idb_SendNotificationResponse {
    try await BridgeFuture.await(commandExecutor.sendPushNotification(forBundleID: request.bundleID, jsonPayload: request.jsonPayload))
    return .init()
  }
}
