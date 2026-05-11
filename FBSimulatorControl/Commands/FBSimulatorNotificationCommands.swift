/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc(FBSimulatorNotificationCommands)
public final class FBSimulatorNotificationCommands: NSObject, FBNotificationCommands {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorNotificationCommands {
    return FBSimulatorNotificationCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - FBNotificationCommands (legacy FBFuture entry point)

  @objc
  public func sendPushNotification(forBundleID bundleID: String, jsonPayload: String) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await sendPushNotificationAsync(forBundleID: bundleID, jsonPayload: jsonPayload)
      return NSNull()
    }
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

    guard FBSimDeviceWrapper.deviceCanSendPushNotification(simulator.device) else {
      throw FBSimulatorError.describe("SimDevice doesn't have sendPushNotificationForBundleID selector").build()
    }

    var error: NSError?
    FBSimDeviceWrapper.sendPushNotification(onDevice: simulator.device, bundleID: bundleID, jsonPayload: jsonObj, error: &error)
    if let error {
      throw error
    }
  }
}

// MARK: - AsyncNotificationCommands

extension FBSimulatorNotificationCommands: AsyncNotificationCommands {

  public func sendPushNotification(forBundleID bundleID: String, jsonPayload: String) async throws {
    try await sendPushNotificationAsync(forBundleID: bundleID, jsonPayload: jsonPayload)
  }
}

// MARK: - FBSimulator+AsyncNotificationCommands

extension FBSimulator: AsyncNotificationCommands {

  public func sendPushNotification(forBundleID bundleID: String, jsonPayload: String) async throws {
    try await notificationCommands().sendPushNotificationAsync(forBundleID: bundleID, jsonPayload: jsonPayload)
  }
}
