/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc(FBSimulatorLogCommands)
public final class FBSimulatorLogCommands: NSObject, FBLogCommands, FBiOSTargetCommand {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorLogCommands {
    return FBSimulatorLogCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - FBLogCommands (legacy FBFuture entry point)

  @objc
  public func tailLog(_ arguments: [String], consumer: any FBDataConsumer) -> FBFuture<FBLogOperation> {
    fbFutureFromAsync { [self] in
      try await tailLogAsync(arguments: arguments, consumer: consumer)
    }
  }

  // MARK: - Private

  fileprivate func tailLogAsync(arguments: [String], consumer: any FBDataConsumer) async throws -> FBLogOperation {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let launchPath = try logExecutablePath()
    let streamArguments = FBProcessLogOperation.osLogArgumentsInsertStreamIfNeeded(arguments)
    let processIO = FBProcessIO<AnyObject, AnyObject, AnyObject>(
      stdIn: nil,
      stdOut: FBProcessOutput<AnyObject>(for: consumer),
      stdErr: nil
    )
    let configuration = FBProcessSpawnConfiguration(
      launchPath: launchPath,
      arguments: streamArguments,
      environment: [:],
      io: processIO,
      mode: .default
    )
    let process = try await bridgeFBFuture(simulator.launchProcess(configuration)) as! FBSubprocess<AnyObject, AnyObject, AnyObject>
    return FBProcessLogOperation(process: process, consumer: consumer, queue: simulator.asyncQueue)
  }

  private func logExecutablePath() throws -> String {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    guard let root = FBSimDeviceWrapper.runtimeRoot(forDevice: simulator.device) else {
      throw FBSimulatorError.describe("Could not obtain runtime root for simulator").build()
    }
    let path =
      (((root as NSString)
      .appendingPathComponent("usr") as NSString)
      .appendingPathComponent("bin") as NSString)
      .appendingPathComponent("log")
    let binary = try FBBinaryDescriptor.binary(withPath: path)
    return binary.path
  }
}

// MARK: - FBSimulator+AsyncLogCommands

extension FBSimulator: AsyncLogCommands {

  public func tailLog(arguments: [String], consumer: any FBDataConsumer) async throws -> any AsyncLogOperation {
    let operation = try await logCommands().tailLogAsync(arguments: arguments, consumer: consumer)
    return AsyncLogOperationBridge(operation)
  }
}
