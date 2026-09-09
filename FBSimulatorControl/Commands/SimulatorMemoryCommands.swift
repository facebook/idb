/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import FBControlCore
import Foundation

public enum FBSimulatorMemoryError: Error, LocalizedError {
  case selectorUnavailable

  public var errorDescription: String? {
    switch self {
    case .selectorUnavailable:
      return "SimDevice doesn't have simulateMemoryWarning selector"
    }
  }
}

public struct FBSimulatorMemoryCommands {

  private let simulator: FBSimulator

  public static func commands(with simulator: FBSimulator) -> FBSimulatorMemoryCommands {
    FBSimulatorMemoryCommands(simulator: simulator)
  }

  fileprivate func simulateMemoryWarning() async throws {
    guard simulator.device.responds(to: NSSelectorFromString("simulateMemoryWarning")) else {
      throw FBSimulatorMemoryError.selectorUnavailable
    }
    simulator.device.simulateMemoryWarning()
  }
}

// MARK: - FBSimulator+MemoryCommands

extension FBSimulator: MemoryCommands {

  public func simulateMemoryWarning() async throws {
    try await memory.simulateMemoryWarning()
  }
}
