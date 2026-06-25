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
    let queue = DispatchQueue.global(qos: .userInitiated)

    // Resolve `mutable` when statLoc completes, but observe via
    // `notifyOfCompletion` instead of `mapReplace`. `mapReplace` wires up an
    // automatic respondToCancellation that cancels the source future when the
    // chain is cancelled. That auto-responder races with our SIGTERM responder
    // below: if it wins, `task.statLoc` becomes cancelled (hasCompleted = YES),
    // and `task.sendSignal:`'s "skip if dead" guard short-circuits without
    // calling `kill()`. Net effect: the process is never signaled.
    let mutable = FBMutableFuture<NSNull>()
    task.statLoc.onQueue(
      queue,
      notifyOfCompletion: { _ in
        mutable.resolve(withResult: NSNull())
      })

    return convertFBMutableFuture(mutable).onQueue(
      queue,
      respondToCancellation: {
        // sendSignal returns FBFuture<NSNumber>. Map to NSNull so the
        // responder's future actually matches its declared return type and
        // the bridge can read its result safely.
        task.sendSignal(SIGTERM, backingOffToKillWithTimeout: 1, logger: nil)
          // swiftlint:disable:next force_cast
          .mapReplace(NSNull()) as! FBFuture<NSNull>
      }
    )
  }
}

// MARK: - FBSimulatorDebuggerCommands

public final class FBSimulatorDebuggerCommands: NSObject, FBiOSTargetCommand {

  // MARK: - Properties

  internal weak var simulator: FBSimulator?
  internal let debugServerPath: String

  // MARK: - Class Methods

  internal class func resolveDebugServerPath() -> String {
    (FBXcodeConfiguration.contentsDirectory as NSString)
      .appendingPathComponent("SharedFrameworks/LLDB.framework/Resources/debugserver")
  }

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> FBSimulatorDebuggerCommands {
    FBSimulatorDebuggerCommands(
      // swiftlint:disable:next force_cast
      simulator: target as! FBSimulator,
      debugServerPath: resolveDebugServerPath()
    )
  }

  internal init(simulator: FBSimulator, debugServerPath: String) {
    self.simulator = simulator
    self.debugServerPath = debugServerPath
    super.init()
  }

  // MARK: - Private

  func launchDebugServer(forHostApplication application: FBBundleDescriptor, port: in_port_t) async throws -> any FBDebugServer {
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
    let launchedApp = try await simulator.launchApplication(configuration)
    // swiftlint:disable:next force_cast
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
    FBProcessBuilder<NSNull, AnyObject, AnyObject>
      .withLaunchPath(debugServerPath)
      .withArguments(["localhost:\(port)", "--attach", "\(processIdentifier)"])
      // swiftlint:disable:next force_unwrapping
      .withStdOut(to: simulator.logger!)
      // swiftlint:disable:next force_unwrapping
      .withStdErr(to: simulator.logger!)
      // swiftlint:disable:next force_cast
      .start() as! FBFuture<AnyObject>
  }
}

// MARK: - FBSimulator+DebuggerCommands

extension FBSimulator: DebuggerCommands {

  public func launchDebugServer(
    forHostApplication application: FBBundleDescriptor,
    port: in_port_t
  ) async throws -> any FBDebugServer {
    try await debuggerCommands().launchDebugServer(forHostApplication: application, port: port)
  }
}
