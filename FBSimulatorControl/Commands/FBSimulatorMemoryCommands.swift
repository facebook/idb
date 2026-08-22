/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import FBControlCore
import Foundation

/// The way memory-warning simulation fails on older CoreSimulators, as data rather than an assembled string.
public enum FBSimulatorMemoryError: Error, LocalizedError {
  case selectorUnavailable

  public var errorDescription: String? {
    switch self {
    case .selectorUnavailable:
      return "SimDevice doesn't have simulateMemoryWarning selector"
    }
  }
}

public final class FBSimulatorMemoryCommands: NSObject {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  public class func commands(with simulator: FBSimulator) -> FBSimulatorMemoryCommands {
    FBSimulatorMemoryCommands(simulator: simulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Private

  fileprivate func simulateMemoryWarningAsync() async throws {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    guard simulator.device.responds(to: NSSelectorFromString("simulateMemoryWarning")) else {
      throw FBSimulatorMemoryError.selectorUnavailable
    }
    simulator.device.simulateMemoryWarning()
  }
}

// MARK: - FBSimulator+MemoryCommands

extension FBSimulator: MemoryCommands {

  public func simulateMemoryWarning() async throws {
    try await memoryCommands().simulateMemoryWarningAsync()
  }
}
