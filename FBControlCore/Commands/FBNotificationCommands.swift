/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBNotificationCommands: NSObjectProtocol, FBiOSTargetCommand {

  @objc(sendPushNotificationForBundleID:jsonPayload:)
  func sendPushNotification(forBundleID bundleID: String, jsonPayload: String) -> FBFuture<NSNull>
}
