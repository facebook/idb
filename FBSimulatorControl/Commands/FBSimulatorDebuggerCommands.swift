/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// swiftlint:disable force_cast

// MARK: - FBSimulatorDebugServer

private class FBSimulatorDebugServer: NSObject, FBDebugServer {

  let task: FBSubprocess<NSNull, AnyObject, AnyObject>
  let lldbBootstrapCommands: [String]

  init(debugServerTask: FBSubprocess<NSNull, AnyObject, AnyObject>, lldbBootstrapCommands: [String]) {
    self.task = debugServerTask
    self.lldbBootstrapCommands = lldbBootstrapCommands
    super.init()
  }

  // MARK: - FBiOSTargetOperation

  var completed: FBFuture<NSNull> {
    let task = self.task
    return
      (task.statLoc
      .mapReplace(NSNull())
      .onQueue(
        DispatchQueue.global(qos: .userInitiated),
        respondToCancellation: {
          return task.sendSignal(SIGTERM, backingOffToKillWithTimeout: 1, logger: nil) as! FBFuture<NSNull>
        }
      )) as! FBFuture<NSNull>
  }
}

// MARK: - FBSimulatorDebuggerCommands

@objc(FBSimulatorDebuggerCommands)
public final class FBSimulatorDebuggerCommands: NSObject, FBDebuggerCommands {

  // MARK: - Properties

  internal weak var simulator: FBSimulator?
  internal let debugServerPath: String

  // MARK: - Class Methods

  internal class func resolveDebugServerPath() -> String {
    return (FBXcodeConfiguration.contentsDirectory as NSString)
      .appendingPathComponent("SharedFrameworks/LLDB.framework/Resources/debugserver")
  }

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorDebuggerCommands {
    return FBSimulatorDebuggerCommands(
      simulator: target as! FBSimulator,
      debugServerPath: resolveDebugServerPath()
    )
  }

  internal init(simulator: FBSimulator, debugServerPath: String) {
    self.simulator = simulator
    self.debugServerPath = debugServerPath
    super.init()
  }

  // MARK: - FBDebuggerCommands (legacy FBFuture entry point)

  @objc
  public func launchDebugServer(forHostApplication application: FBBundleDescriptor, port: in_port_t) -> FBFuture<any FBDebugServer> {
    fbFutureFromAsync { [self] in
      try await launchDebugServerAsync(forHostApplication: application, port: port)
    }
  }

  // MARK: - Private

  fileprivate func launchDebugServerAsync(forHostApplication application: FBBundleDescriptor, port: in_port_t) async throws -> any FBDebugServer {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let configuration = FBApplicationLaunchConfiguration(
      bundleID: application.identifier,
      bundleName: application.name,
      arguments: [],
      environment: [:],
      waitForDebugger: true,
      io: FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull(),
      launchMode: .failIfRunning
    )
    let launchedApp = try await bridgeFBFuture(simulator.launchApplication(configuration)) as! FBLaunchedApplication
    let debugTask = try await bridgeFBFuture(debugServerTask(forPort: port, processIdentifier: launchedApp.processIdentifier, simulator: simulator, debugServerPath: debugServerPath)) as! FBSubprocess<NSNull, AnyObject, AnyObject>
    let lldbBootstrapCommands = [
      "process connect connect://localhost:\(port)"
    ]
    return FBSimulatorDebugServer(
      debugServerTask: debugTask,
      lldbBootstrapCommands: lldbBootstrapCommands
    )
  }

  private func debugServerTask(forPort port: in_port_t, processIdentifier: pid_t, simulator: FBSimulator, debugServerPath: String) -> FBFuture<AnyObject> {
    return FBProcessBuilder<NSNull, AnyObject, AnyObject>
      .withLaunchPath(debugServerPath)
      .withArguments(["localhost:\(port)", "--attach", "\(processIdentifier)"])
      .withStdOut(to: simulator.logger!)
      .withStdErr(to: simulator.logger!)
      .start() as! FBFuture<AnyObject>
  }
}

// MARK: - AsyncDebuggerCommands

extension FBSimulatorDebuggerCommands: AsyncDebuggerCommands {

  public func launchDebugServer(
    forHostApplication application: FBBundleDescriptor,
    port: in_port_t
  ) async throws -> any FBDebugServer {
    try await launchDebugServerAsync(forHostApplication: application, port: port)
  }
}

// MARK: - FBSimulator+AsyncDebuggerCommands

extension FBSimulator: AsyncDebuggerCommands {

  public func launchDebugServer(
    forHostApplication application: FBBundleDescriptor,
    port: in_port_t
  ) async throws -> any FBDebugServer {
    try await debuggerCommands().launchDebugServer(forHostApplication: application, port: port)
  }
}
