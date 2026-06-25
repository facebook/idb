/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// swiftlint:disable force_cast

@preconcurrency import CoreSimulator
import FBControlCore
import Foundation

public final class FBSimulatorLocationCommands: NSObject, FBiOSTargetCommand {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> FBSimulatorLocationCommands {
    FBSimulatorLocationCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Private

  fileprivate func overrideLocationAsync(longitude: Double, latitude: Double) async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    try simulator.device.setLocationWithLatitude(latitude, andLongitude: longitude)
  }
}

// MARK: - FBSimulator+LocationCommands

extension FBSimulator: LocationCommands {

  public func overrideLocation(longitude: Double, latitude: Double) async throws {
    try await locationCommands().overrideLocationAsync(longitude: longitude, latitude: latitude)
  }
}
