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

  // MARK: - FBNotificationCommands

  @objc
  public func sendPushNotification(forBundleID bundleID: String, jsonPayload: String) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBFuture(error: FBSimulatorError.describe("Simulator deallocated").build())
    }

    guard let data = jsonPayload.data(using: .utf8) else {
      return
        FBSimulatorError
        .describe("Failed to encode notification json as UTF-8")
        .failFuture() as! FBFuture<NSNull>
    }
    let jsonObj: [String: Any]
    do {
      guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return
          FBSimulatorError
          .describe("Failed to deserialize notification json: not a dictionary")
          .failFuture() as! FBFuture<NSNull>
      }
      jsonObj = parsed
    } catch {
      return
        FBSimulatorError
        .describe("Failed to deserialize notification json: \(error)")
        .failFuture() as! FBFuture<NSNull>
    }

    if FBSimDeviceWrapper.deviceCanSendPushNotification(simulator.device) {
      return FBFuture.onQueue(
        simulator.workQueue,
        resolve: { () -> FBFuture<AnyObject> in
          var error: NSError?
          FBSimDeviceWrapper.sendPushNotification(onDevice: simulator.device, bundleID: bundleID, jsonPayload: jsonObj, error: &error)
          if let error = error {
            return FBFuture(error: error)
          }
          return FBFuture<NSNull>.empty() as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
    }

    return
      FBSimulatorError
      .describe("SimDevice doesn't have sendPushNotificationForBundleID selector")
      .failFuture() as! FBFuture<NSNull>
  }
}
