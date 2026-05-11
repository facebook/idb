/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc(FBSimulatorMemoryCommands)
public final class FBSimulatorMemoryCommands: NSObject, FBiOSTargetCommand {

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

  // MARK: - FBMemoryCommands (legacy FBFuture entry point)

  @objc
  public func simulateMemoryWarning() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await simulateMemoryWarningAsync()
      return NSNull()
    }
  }

  // MARK: - Private

  fileprivate func simulateMemoryWarningAsync() async throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    guard FBSimDeviceWrapper.deviceCanSimulateMemoryWarning(simulator.device) else {
      throw FBSimulatorError.describe("SimDevice doesn't have simulateMemoryWarning selector").build()
    }
    FBSimDeviceWrapper.simulateMemoryWarning(onDevice: simulator.device)
  }
}

// MARK: - AsyncMemoryCommands

extension FBSimulatorMemoryCommands: AsyncMemoryCommands {

  public func simulateMemoryWarning() async throws {
    try await simulateMemoryWarningAsync()
  }
}

// MARK: - FBSimulator+AsyncMemoryCommands

extension FBSimulator: AsyncMemoryCommands {

  public func simulateMemoryWarning() async throws {
    try await memoryCommands().simulateMemoryWarningAsync()
  }
}
