/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// swiftlint:disable force_cast

import FBControlCore
import Foundation

@objc(FBSimulatorLocationCommands)
public final class FBSimulatorLocationCommands: NSObject, FBiOSTargetCommand {

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

  // MARK: - FBLocationCommands (legacy FBFuture entry point)

  @objc
  public func overrideLocation(withLongitude longitude: Double, latitude: Double) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await overrideLocationAsync(longitude: longitude, latitude: latitude)
      return NSNull()
    }
  }

  // MARK: - Private

  fileprivate func overrideLocationAsync(longitude: Double, latitude: Double) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try FBSimDeviceWrapper.setLocationOnDevice(simulator.device, latitude: latitude, longitude: longitude)
  }
}

// MARK: - FBSimulator+AsyncLocationCommands

extension FBSimulator: AsyncLocationCommands {

  public func overrideLocation(longitude: Double, latitude: Double) async throws {
    try await locationCommands().overrideLocationAsync(longitude: longitude, latitude: latitude)
  }
}
