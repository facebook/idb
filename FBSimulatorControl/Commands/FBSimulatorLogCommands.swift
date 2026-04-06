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

  // MARK: - FBLogCommands

  @objc
  public func tailLog(_ arguments: [String], consumer: any FBDataConsumer) -> FBFuture<FBLogOperation> {
    guard let simulator = self.simulator else {
      return FBFuture(error: FBSimulatorError.describe("Simulator deallocated").build())
    }
    let launchPath: String
    do {
      launchPath = try logExecutablePath()
    } catch {
      return FBFuture(error: error)
    }
    let streamArguments = FBProcessLogOperation.osLogArgumentsInsertStreamIfNeeded(arguments)
    let processIO = FBProcessIO<AnyObject, AnyObject, AnyObject>(
      stdIn: nil,
      stdOut: FBProcessOutput<AnyObject>(for: consumer),
      stdErr: nil
    )
    let configuration = FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>(
      launchPath: launchPath,
      arguments: streamArguments,
      environment: [:],
      io: processIO,
      mode: .default
    )
    return (simulator.launchProcess(configuration)
      .onQueue(simulator.workQueue, map: { process -> AnyObject in
        return FBProcessLogOperation(process: process, consumer: consumer, queue: simulator.asyncQueue)
      }) as! FBFuture<FBLogOperation>)
  }

  // MARK: - Private

  private func logExecutablePath() throws -> String {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    guard let root = FBSimDeviceWrapper.runtimeRoot(forDevice: simulator.device) else {
      throw FBSimulatorError.describe("Could not obtain runtime root for simulator").build()
    }
    let path = (((root as NSString)
      .appendingPathComponent("usr") as NSString)
      .appendingPathComponent("bin") as NSString)
      .appendingPathComponent("log")
    let binary = try FBBinaryDescriptor.binary(withPath: path)
    return binary.path
  }
}
