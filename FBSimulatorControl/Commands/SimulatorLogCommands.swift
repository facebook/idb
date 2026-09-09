/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import FBControlCore
import Foundation

public enum FBSimulatorLogError: Error, LocalizedError {
  case runtimeRootUnavailable

  public var errorDescription: String? {
    switch self {
    case .runtimeRootUnavailable:
      return "Could not obtain runtime root for simulator"
    }
  }
}

public struct FBSimulatorLogCommands {

  private let simulator: FBSimulator

  public static func commands(with simulator: FBSimulator) -> FBSimulatorLogCommands {
    FBSimulatorLogCommands(simulator: simulator)
  }

  fileprivate func tailLog(arguments: [String], consumer: any FBDataConsumer) async throws -> any LogOperation {
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
    return try await log.tailLog(arguments: arguments, consumer: consumer)
  }
}
