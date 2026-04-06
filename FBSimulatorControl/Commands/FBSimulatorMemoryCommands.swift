/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc(FBSimulatorMemoryCommands)
public final class FBSimulatorMemoryCommands: NSObject, FBMemoryCommands {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorMemoryCommands {
    return FBSimulatorMemoryCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - FBMemoryCommands

  @objc
  public func simulateMemoryWarning() -> FBFuture<NSNull> {
    guard let simulator = self.simulator else {
      return FBFuture(error: FBSimulatorError.describe("Simulator deallocated").build())
    }
    if FBSimDeviceWrapper.deviceCanSimulateMemoryWarning(simulator.device) {
      return FBFuture.onQueue(
        simulator.workQueue,
        resolve: { () -> FBFuture<AnyObject> in
          FBSimDeviceWrapper.simulateMemoryWarning(onDevice: simulator.device)
          return FBFuture<NSNull>.empty() as! FBFuture<AnyObject>
        }) as! FBFuture<NSNull>
    }

    return
      FBSimulatorError
      .describe("SimDevice doesn't have simulateMemoryWarning selector")
      .failFuture() as! FBFuture<NSNull>
  }
}
