/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// MARK: - SimulatorDebugServer

private final class SimulatorDebugServer: DebugServer {

  let process: RunningSubprocess
  let lldbBootstrapCommands: [String]

  init(process: RunningSubprocess, lldbBootstrapCommands: [String]) {
    self.process = process
    self.lldbBootstrapCommands = lldbBootstrapCommands
  }

  // MARK: - DebugServer

  func cancel() async throws {
    await process.terminate(gracePeriod: 1)
  }
}

public final class SimulatorDebugServerCommands: DebugServerCommands {

  internal weak var simulator: Simulator?
  internal let debugServerPath: String

  /// How the host application is launched; defaults to the simulator itself.
  private let applicationLauncher: (any ApplicationLaunching)?

  internal static func resolveDebugServerPath() -> String {
    (XcodeConfiguration.contentsDirectory as NSString)
      .appendingPathComponent("SharedFrameworks/LLDB.framework/Resources/debugserver")
  }

  public static func commands(with simulator: Simulator) -> SimulatorDebugServerCommands {
    SimulatorDebugServerCommands(
      simulator: simulator,
      debugServerPath: resolveDebugServerPath()
    )
  }

  internal init(
    simulator: Simulator,
    debugServerPath: String,
    applicationLauncher: (any ApplicationLaunching)? = nil
  ) {
    self.simulator = simulator
    self.debugServerPath = debugServerPath
    self.applicationLauncher = applicationLauncher
  }

  public func launch(forHostApplication application: BundleDescriptor, port: in_port_t) async throws -> any DebugServer {
    guard let simulator = self.simulator else {
      throw WeakTargetError.simulator
    }
    let configuration = ApplicationLaunchConfiguration(
      bundleID: application.identifier,
      bundleName: application.name,
      arguments: [],
      environment: [:],
      waitForDebugger: true,
      launchMode: .failIfRunning
    )
    let launchedApp = try await (applicationLauncher ?? simulator.application).launch(configuration)
    let process = try await Subprocess(
      executable: debugServerPath,
      arguments: ["localhost:\(port)", "--attach", "\(launchedApp.processIdentifier)"]
    )
    .launch(output: .logger(simulator.logger), error: .logger(simulator.logger))
    let lldbBootstrapCommands = [
      "process connect connect://localhost:\(port)"
    ]
    return SimulatorDebugServer(
      process: process,
      lldbBootstrapCommands: lldbBootstrapCommands
    )
  }
}
