/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import FBControlCore
import Foundation

public enum SimulatorNotificationError: Error {
  case jsonNotUTF8
  case jsonNotADictionary
  case selectorUnavailable
}

extension SimulatorNotificationError: LocalizedError {
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

public struct SimulatorNotificationCommands {

  private let simulator: FBSimulator

  public static func commands(with simulator: FBSimulator) -> SimulatorNotificationCommands {
    SimulatorNotificationCommands(simulator: simulator)
  }

  public func sendPushNotification(forBundleID bundleID: String, jsonPayload: String) async throws {

    guard let data = jsonPayload.data(using: .utf8) else {
      throw SimulatorNotificationError.jsonNotUTF8
    }
    guard let jsonObj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw SimulatorNotificationError.jsonNotADictionary
    }

    guard simulator.device.responds(to: NSSelectorFromString("sendPushNotificationForBundleID:jsonPayload:error:")) else {
      throw SimulatorNotificationError.selectorUnavailable
    }

    try simulator.device.sendPushNotification(forBundleID: bundleID, jsonPayload: jsonObj)
  }
}
