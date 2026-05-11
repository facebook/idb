/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc(FBSimulatorDapServerCommand)
public final class FBSimulatorDapServerCommand: NSObject, FBiOSTargetCommand {

  // MARK: - Properties

  private let simulator: FBSimulator

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorDapServerCommand {
    return FBSimulatorDapServerCommand(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - FBDapServerCommand (legacy FBFuture entry point)

  @objc
  public func launchDapServer(_ dapPath: Any, stdIn: FBProcessInput<AnyObject>, stdOut: any FBDataConsumer) -> FBFuture<FBSubprocess<AnyObject, any FBDataConsumer, NSString>> {
    fbFutureFromAsync { [self] in
      try await launchDapServerAsync(dapPath, stdIn: stdIn, stdOut: stdOut)
    }
  }

  // MARK: - Private

  fileprivate func launchDapServerAsync(_ dapPath: Any, stdIn: FBProcessInput<AnyObject>, stdOut: any FBDataConsumer) async throws -> FBSubprocess<AnyObject, any FBDataConsumer, NSString> {
    let dapLogDir = (simulator.coreSimulatorLogsDirectory as NSString).appendingPathComponent("dap")

    do {
      try FileManager.default.createDirectory(atPath: dapLogDir, withIntermediateDirectories: true, attributes: nil)
    } catch {
      throw
        FBControlCoreError
        .describe("Dap Command: Failed to create log director on path \(dapLogDir). Error: \(error.localizedDescription)")
        .build()
    }

    let logString = (dapLogDir as NSString).appendingPathComponent(UUID().uuidString + ".log")
    let createdLogFile = FileManager.default.createFile(atPath: logString, contents: nil, attributes: nil)
    if !createdLogFile {
      throw
        FBControlCoreError
        .describe("Failed to create log file on path \(logString)")
        .build()
    }

    simulator.logger?.debug().log("Dap Command: Launching dap server logging at path \(logString)")
    let envs: [String: String] = [
      "LLDBVSCODE_LOG": logString
    ]
    guard let dataDirectory = simulator.dataDirectory else {
      throw FBControlCoreError.describe("Simulator has no data directory").build()
    }
    let fullPath = (dataDirectory as NSString).appendingPathComponent(dapPath as! String)
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

// MARK: - AsyncDapServerCommand

extension FBSimulatorDapServerCommand: AsyncDapServerCommand {

  public func launchDapServer(
    _ dapPath: Any,
    stdIn: FBProcessInput<AnyObject>,
    stdOut: any FBDataConsumer
  ) async throws -> FBSubprocess<AnyObject, FBDataConsumer, NSString> {
    try await launchDapServerAsync(dapPath, stdIn: stdIn, stdOut: stdOut)
  }
}

// MARK: - FBSimulator+AsyncDapServerCommand

extension FBSimulator: AsyncDapServerCommand {

  public func launchDapServer(
    _ dapPath: Any,
    stdIn: FBProcessInput<AnyObject>,
    stdOut: any FBDataConsumer
  ) async throws -> FBSubprocess<AnyObject, FBDataConsumer, NSString> {
    try await dapServerCommand().launchDapServerAsync(dapPath, stdIn: stdIn, stdOut: stdOut)
  }
}
