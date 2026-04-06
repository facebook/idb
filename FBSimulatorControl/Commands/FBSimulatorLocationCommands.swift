/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc(FBSimulatorLocationCommands)
public final class FBSimulatorLocationCommands: NSObject, FBLocationCommands {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorLocationCommands {
    return FBSimulatorLocationCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - FBLocationCommands

  @objc
  public func overrideLocation(withLongitude longitude: Double, latitude: Double) -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBFuture(error: FBSimulatorError.describe("Simulator deallocated").build())
    }
    if FBSimDeviceWrapper.deviceCanSetLocation(simulator.device) {
      return FBFuture.onQueue(
        simulator.workQueue,
        resolve: { () -> FBFuture<AnyObject> in
          do {
            try FBSimDeviceWrapper.setLocationOnDevice(simulator.device, latitude: latitude, longitude: longitude)
            return FBFuture<NSNull>.empty() as! FBFuture<AnyObject>
          } catch {
            return FBFuture(error: error)
          }
        }) as! FBFuture<NSNull>
    }

    return
      (simulator.connectToBridge()
      .onQueue(
        simulator.workQueue,
        fmap: { bridge -> FBFuture<AnyObject> in
          return unsafeBitCast(bridge.setLocationWithLatitude(latitude, longitude: longitude), to: FBFuture<AnyObject>.self)
        }) as! FBFuture<NSNull>)
  }
}
