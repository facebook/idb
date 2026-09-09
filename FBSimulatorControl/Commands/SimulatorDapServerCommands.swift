/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public enum FBSimulatorDapServerError: Error {
  case logDirectoryCreationFailed(path: String, underlying: Error)
  case logFileCreationFailed(path: String)
  case noDataDirectory
}

extension FBSimulatorDapServerError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .logDirectoryCreationFailed(path, underlying):
      return "Dap Command: Failed to create log director on path \(path). Error: \(underlying.localizedDescription)"
    case let .logFileCreationFailed(path):
      return "Failed to create log file on path \(path)"
    case .noDataDirectory:
      return "Simulator has no data directory"
    }
  }
}

public final class FBSimulatorDapServerCommand {

  private let simulator: FBSimulator

  public class func commands(with simulator: FBSimulator) -> FBSimulatorDapServerCommand {
    FBSimulatorDapServerCommand(simulator: simulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  fileprivate func launchDapServer(_ dapPath: String, stdIn: FBProcessInput<AnyObject>, stdOut: any FBDataConsumer) async throws -> FBSubprocess<AnyObject, any FBDataConsumer, NSString> {
    let dapLogDir = (simulator.coreSimulatorLogsDirectory as NSString).appendingPathComponent("dap")

    do {
      try FileManager.default.createDirectory(atPath: dapLogDir, withIntermediateDirectories: true, attributes: nil)
    } catch {
      throw FBSimulatorDapServerError.logDirectoryCreationFailed(path: dapLogDir, underlying: error)
    }

    let logString = (dapLogDir as NSString).appendingPathComponent(UUID().uuidString + ".log")
    let createdLogFile = FileManager.default.createFile(atPath: logString, contents: nil, attributes: nil)
    if !createdLogFile {
      throw FBSimulatorDapServerError.logFileCreationFailed(path: logString)
    }

    simulator.logger.debug().log("Dap Command: Launching dap server logging at path \(logString)")
    let envs: [String: String] = [
      "LLDBVSCODE_LOG": logString
    ]
    guard let dataDirectory = simulator.dataDirectory else {
      throw FBSimulatorDapServerError.noDataDirectory
    }
    let fullPath = (dataDirectory as NSString).appendingPathComponent(dapPath)
    let startedFuture = FBProcessBuilder<AnyObject, AnyObject, NSString>
      .withLaunchPath(fullPath)
      .withEnvironment(envs)
      .withStdIn(stdIn)
      .withStdOutConsumer(stdOut)
      .withStdErrInMemoryAsString()
      .start()
    return try await bridgeFBFuture(startedFuture)
  }
}

// MARK: - FBSimulator+DapServerCommand

extension FBSimulator: DapServerCommand {

  public func launchDapServer(
    _ dapPath: String,
    stdIn: FBProcessInput<AnyObject>,
    stdOut: any FBDataConsumer
  ) async throws -> FBSubprocess<AnyObject, FBDataConsumer, NSString> {
    try await dapServer.launchDapServer(dapPath, stdIn: stdIn, stdOut: stdOut)
  }
}
