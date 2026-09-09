/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import FBControlCore
import Foundation

public enum FBSimulatorNotificationError: Error {
  case jsonNotUTF8
  case jsonNotADictionary
  case selectorUnavailable
}

extension FBSimulatorNotificationError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .jsonNotUTF8:
      return "Failed to encode notification json as UTF-8"
    case .jsonNotADictionary:
      return "Failed to deserialize notification json: not a dictionary"
    case .selectorUnavailable:
      return "SimDevice doesn't have sendPushNotificationForBundleID selector"
    }
  }
}

public struct FBSimulatorNotificationCommands {

  private let simulator: FBSimulator

  public static func commands(with simulator: FBSimulator) -> FBSimulatorNotificationCommands {
    FBSimulatorNotificationCommands(simulator: simulator)
  }

  fileprivate func sendPushNotification(forBundleID bundleID: String, jsonPayload: String) async throws {

    guard let data = jsonPayload.data(using: .utf8) else {
      throw FBSimulatorNotificationError.jsonNotUTF8
    }
    guard let jsonObj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw FBSimulatorNotificationError.jsonNotADictionary
    }

    guard simulator.device.responds(to: NSSelectorFromString("sendPushNotificationForBundleID:jsonPayload:error:")) else {
      throw FBSimulatorNotificationError.selectorUnavailable
    }

    try simulator.device.sendPushNotification(forBundleID: bundleID, jsonPayload: jsonObj)
  }
}

// MARK: - FBSimulator+NotificationCommands

extension FBSimulator: NotificationCommands {

  public func sendPushNotification(forBundleID bundleID: String, jsonPayload: String) async throws {
    try await notification.sendPushNotification(forBundleID: bundleID, jsonPayload: jsonPayload)
  }
}
