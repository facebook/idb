/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import FBControlCore
import Foundation

@objc(FBSimulatorNotificationCommands)
public final class FBSimulatorNotificationCommands: NSObject, FBiOSTargetCommand {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorNotificationCommands {
    FBSimulatorNotificationCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Private

  fileprivate func sendPushNotificationAsync(forBundleID bundleID: String, jsonPayload: String) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }

    guard let data = jsonPayload.data(using: .utf8) else {
      throw FBSimulatorError.describe("Failed to encode notification json as UTF-8").build()
    }
    guard let jsonObj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw FBSimulatorError.describe("Failed to deserialize notification json: not a dictionary").build()
    }

    guard simulator.device.responds(to: NSSelectorFromString("sendPushNotificationForBundleID:jsonPayload:error:")) else {
      throw FBSimulatorError.describe("SimDevice doesn't have sendPushNotificationForBundleID selector").build()
    }

    try simulator.device.sendPushNotification(forBundleID: bundleID, jsonPayload: jsonObj)
  }
}

// MARK: - FBSimulator+NotificationCommands

extension FBSimulator: NotificationCommands {

  public func sendPushNotification(forBundleID bundleID: String, jsonPayload: String) async throws {
    try await notificationCommands().sendPushNotificationAsync(forBundleID: bundleID, jsonPayload: jsonPayload)
  }
}
