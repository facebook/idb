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

  // MARK: - Properties

  private let simulator: FBSimulator

  // MARK: - Initializers

  public static func commands(with simulator: FBSimulator) -> FBSimulatorLocationCommands {
    FBSimulatorLocationCommands(simulator: simulator)
  }

  // MARK: - Private

  fileprivate func overrideLocationAsync(longitude: Double, latitude: Double) async throws {
    try simulator.device.setLocationWithLatitude(latitude, andLongitude: longitude)
  }
}

// MARK: - FBSimulator+LocationCommands

extension FBSimulator: LocationCommands {

  public func overrideLocation(longitude: Double, latitude: Double) async throws {
    try await locationCommands().overrideLocationAsync(longitude: longitude, latitude: latitude)
  }
}
