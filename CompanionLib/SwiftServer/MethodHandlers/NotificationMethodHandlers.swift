/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import GRPCCore
import IDBGRPCSwift

struct SendNotificationMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_SendNotificationRequest, context: ServerContext) async throws -> Idb_SendNotificationResponse {
    try await commandExecutor.sendPushNotification(forBundleID: request.bundleID, jsonPayload: request.jsonPayload)
    return .init()
  }
}

struct DeliveredNotificationsMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_DeliveredNotificationsRequest, context: ServerContext) async throws -> Idb_DeliveredNotificationsResponse {
    let notifications = try await commandExecutor.deliveredNotifications(forBundleID: request.bundleID)
    return .with {
      $0.notifications = notifications.map { notification in
        Idb_DeliveredNotification.with {
          $0.bundleID = notification.bundleID
          $0.identifier = notification.identifier
          $0.title = notification.title
          $0.subtitle = notification.subtitle
          $0.body = notification.body
          $0.threadIdentifier = notification.threadIdentifier
          if let date = notification.date {
            $0.date = date
          }
        }
      }
    }
  }
}

struct ClearDeliveredNotificationsMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_ClearDeliveredNotificationsRequest, context: ServerContext) async throws -> Idb_ClearDeliveredNotificationsResponse {
    try await commandExecutor.clearDeliveredNotifications(forBundleID: request.bundleID)
    return .init()
  }
}
