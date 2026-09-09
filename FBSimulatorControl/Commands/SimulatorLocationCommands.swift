/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import FBControlCore
import Foundation

public struct FBSimulatorLocationCommands {

  private let simulator: FBSimulator

  public static func commands(with simulator: FBSimulator) -> FBSimulatorLocationCommands {
    FBSimulatorLocationCommands(simulator: simulator)
  }

  fileprivate func overrideLocation(longitude: Double, latitude: Double) async throws {
    try simulator.device.setLocationWithLatitude(latitude, andLongitude: longitude)
  }
}

// MARK: - FBSimulator+LocationCommands

extension FBSimulator: LocationCommands {

  public func overrideLocation(longitude: Double, latitude: Double) async throws {
    try await location.overrideLocation(longitude: longitude, latitude: latitude)
  }
}
