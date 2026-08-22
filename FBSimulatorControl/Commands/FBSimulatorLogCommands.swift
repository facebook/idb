/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import FBControlCore
import Foundation

/// The way log invocation fails without a runtime root, as data rather than an assembled string.
public enum FBSimulatorLogError: Error, LocalizedError {
  case runtimeRootUnavailable

  public var errorDescription: String? {
    switch self {
    case .runtimeRootUnavailable:
      return "Could not obtain runtime root for simulator"
    }
  }
}

public final class FBSimulatorLogCommands: NSObject {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  public class func commands(with simulator: FBSimulator) -> FBSimulatorLogCommands {
    FBSimulatorLogCommands(simulator: simulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Private

  fileprivate func tailLogAsync(arguments: [String], consumer: any FBDataConsumer) async throws -> any LogOperation {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
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
    let process = try await simulator.launchProcess(configuration)
    return FBProcessLogOperation(process: process, consumer: consumer, queue: simulator.asyncQueue)
  }

  private func logExecutablePath() throws -> String {
    guard let simulator = self.simulator else {
      throw FBWeakTargetError.simulator
    }
    guard let root = simulator.device.runtime.root else {
      throw FBSimulatorLogError.runtimeRootUnavailable
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

// MARK: - FBSimulator+LogCommands

extension FBSimulator: LogCommands {

  public func tailLog(arguments: [String], consumer: any FBDataConsumer) async throws -> any LogOperation {
    return try await logCommands().tailLogAsync(arguments: arguments, consumer: consumer)
  }
}
