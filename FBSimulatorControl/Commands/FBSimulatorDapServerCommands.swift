// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import FBControlCore
import Foundation

@objc(FBSimulatorDapServerCommand)
public final class FBSimulatorDapServerCommand: NSObject, FBDapServerCommand, FBiOSTargetCommand {

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

  // MARK: - FBDapServerCommand

  @objc
  public func launchDapServer(_ dapPath: Any!, stdIn: FBProcessInput<AnyObject>, stdOut: any FBDataConsumer) -> FBFuture<FBSubprocess<AnyObject, any FBDataConsumer, NSString>> {
    let dapLogDir = (simulator.coreSimulatorLogsDirectory as NSString).appendingPathComponent("dap")

    do {
      try FileManager.default.createDirectory(atPath: dapLogDir, withIntermediateDirectories: true, attributes: nil)
    } catch {
      return
        FBControlCoreError
        .describe("Dap Command: Failed to create log director on path \(dapLogDir). Error: \(error.localizedDescription)")
        .failFuture() as! FBFuture<FBSubprocess<AnyObject, any FBDataConsumer, NSString>>
    }

    let logString = (dapLogDir as NSString).appendingPathComponent(UUID().uuidString + ".log")
    let createdLogFile = FileManager.default.createFile(atPath: logString, contents: nil, attributes: nil)
    if !createdLogFile {
      return
        FBControlCoreError
        .describe("Failed to create log file on path \(logString)")
        .failFuture() as! FBFuture<FBSubprocess<AnyObject, any FBDataConsumer, NSString>>
    }

    simulator.logger?.debug().log("Dap Command: Launching dap server logging at path \(logString)")
    let envs: [String: String] = [
      "LLDBVSCODE_LOG": logString
    ]
    guard let dataDirectory = simulator.dataDirectory else {
      return
        FBControlCoreError
        .describe("Simulator has no data directory")
        .failFuture() as! FBFuture<FBSubprocess<AnyObject, any FBDataConsumer, NSString>>
    }
    let fullPath = (dataDirectory as NSString).appendingPathComponent(dapPath as! String)
    return FBProcessBuilder<AnyObject, AnyObject, NSString>
      .withLaunchPath(fullPath)
      .withEnvironment(envs)
      .withStdIn(stdIn)
      .withStdOutConsumer(stdOut)
      .withStdErrInMemoryAsString()
      .start()
  }
}
