/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

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

  private weak var simulator: FBSimulator?
  private let debugServerPath: String

  // MARK: - Class Methods

  private class func resolveDebugServerPath() -> String {
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

  private init(simulator: FBSimulator, debugServerPath: String) {
    self.simulator = simulator
    self.debugServerPath = debugServerPath
    super.init()
  }

  // MARK: - FBDebuggerCommands

  @objc
  public func launchDebugServer(forHostApplication application: FBBundleDescriptor, port: in_port_t) -> FBFuture<any FBDebugServer> {
    guard let simulator = self.simulator else {
      return FBFuture(error: FBSimulatorError.describe("Simulator deallocated").build())
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
    let debugServerPath = self.debugServerPath
    return
      (simulator.launchApplication(configuration)
      .onQueue(
        simulator.workQueue,
        fmap: { [weak self] (process: Any) -> FBFuture<AnyObject> in
          guard let self else {
            return FBFuture(error: FBSimulatorError.describe("Commands deallocated").build())
          }
          let launchedApp = process as! FBLaunchedApplication
          return self.debugServerTask(forPort: port, processIdentifier: launchedApp.processIdentifier, simulator: simulator, debugServerPath: debugServerPath)
        }
      )
      .onQueue(
        simulator.workQueue,
        map: { (task: Any) -> AnyObject in
          let debugTask = task as! FBSubprocess<NSNull, AnyObject, AnyObject>
          let lldbBootstrapCommands = [
            "process connect connect://localhost:\(port)"
          ]
          return FBSimulatorDebugServer(
            debugServerTask: debugTask,
            lldbBootstrapCommands: lldbBootstrapCommands
          )
        })) as! FBFuture<any FBDebugServer>
  }

  // MARK: - Private

  private func debugServerTask(forPort port: in_port_t, processIdentifier: pid_t, simulator: FBSimulator, debugServerPath: String) -> FBFuture<AnyObject> {
    return FBProcessBuilder<NSNull, AnyObject, AnyObject>
      .withLaunchPath(debugServerPath)
      .withArguments(["localhost:\(port)", "--attach", "\(processIdentifier)"])
      .withStdOut(to: simulator.logger!)
      .withStdErr(to: simulator.logger!)
      .start() as! FBFuture<AnyObject>
  }
}
