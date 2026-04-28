/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBNotificationCommands`.
public protocol AsyncNotificationCommands: AnyObject {

  func sendPushNotification(forBundleID bundleID: String, jsonPayload: String) async throws
}

/// Default bridge implementation against the legacy `FBNotificationCommands`
/// protocol.
extension AsyncNotificationCommands where Self: FBNotificationCommands {

  public func sendPushNotification(forBundleID bundleID: String, jsonPayload: String) async throws {
    try await bridgeFBFutureVoid(self.sendPushNotification(forBundleID: bundleID, jsonPayload: jsonPayload))
  }
}
