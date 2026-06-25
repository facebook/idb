/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
@preconcurrency import XCTestBootstrap

public final class FBSimulatorReplCommands: NSObject, FBiOSTargetCommand {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> FBSimulatorReplCommands {
    // swiftlint:disable:next force_cast
    return FBSimulatorReplCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Async

  fileprivate func startReplTestAsync(bundlePath: String) async throws -> ReplSession {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator is deallocated").build()
    }
    guard let logger = simulator.logger else {
      throw FBSimulatorError.describe("Simulator has no logger").build()
    }

    // Resolve the REPL shim, which is bundled alongside the other shims.
    let shimDirectory = try await bridgeFBFuture(FBXCTestShimConfiguration.findShimDirectory(onQueue: simulator.workQueue, logger: logger))
    let replDylibPath = shimDirectory.appendingPathComponent("libRepl-iOS.dylib")
    guard FileManager.default.fileExists(atPath: replDylibPath) else {
      throw FBSimulatorError.describe("REPL shim not found at expected location \(replDylibPath)").build()
    }

    // The shim binds this socket; the gRPC handler connects to it.
    let socketPath = "/tmp/idb_repl_\(UUID().uuidString).sock"

    let bundle = try FBBundleDescriptor.bundle(fromPath: bundlePath)
    let architectures = Set((bundle.binary?.architectures ?? []).map(\.rawValue))

    let configuration = FBLogicTestConfiguration(
      environment: ["IDB_REPL_SOCKET_PATH": socketPath],
      workingDirectory: simulator.auxillaryDirectory,
      testBundlePath: bundlePath,
      waitForDebugger: false,
      timeout: 3_600, // 1 hour
      testFilter: "TestRepl/start",
      mirroring: .fileLogs,
      coverageConfiguration: nil,
      binaryPath: bundle.binary?.path,
      logDirectoryPath: nil,
      architectures: architectures,
      injectLibraries: [replDylibPath]
    )

    let runner = FBLogicTestRunStrategy(
      target: simulator as any FBiOSTarget & ProcessSpawnCommands & XCTestExtendedCommands,
      configuration: configuration,
      reporter: ReplNullReporter(),
      logger: logger)
    return ReplSession(socketPath: socketPath, run: runner.execute())
  }

  fileprivate func startReplSimulatorAsync() async throws -> ReplSession {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator is deallocated").build()
    }

    // The SimulatorFrameworkBridge binary is bundled alongside the shims.
    guard let bridgePath = Bundle(for: FBSimulatorReplCommands.self).path(forResource: "SimulatorFrameworkBridge", ofType: nil) else {
      throw FBSimulatorError.describe("SimulatorFrameworkBridge binary not found in bundle resources").build()
    }

    // The bridge's `repl start` action takes the socket path as its argument and
    // serves the control socket there. Serving blocks until the socket is
    // closed, which is what keeps the session alive.
    let socketPath = "/tmp/idb_repl_\(UUID().uuidString).sock"

    let io: FBProcessIO<AnyObject, AnyObject, AnyObject> = .outputToDevNull()
    let configuration = FBProcessSpawnConfiguration(
      launchPath: bridgePath,
      arguments: ["repl", "start", socketPath],
      environment: [:],
      io: io,
      mode: .posixSpawn
    )

    // Launch without waiting; `statLoc` completes when the bridge exits (once
    // the socket is closed), matching the `ReplSession.run` contract.
    let process = try await simulator.launchProcess(configuration)
    let run = unsafeBitCast(process.statLoc, to: FBFuture<NSNull>.self)
    return ReplSession(socketPath: socketPath, run: run)
  }
}

// MARK: - FBSimulator+ReplCommands

extension FBSimulator: ReplCommands {

  public func startReplTest(bundlePath: String) async throws -> ReplSession {
    try await replCommands().startReplTestAsync(bundlePath: bundlePath)
  }

  public func startReplSimulator() async throws -> ReplSession {
    try await replCommands().startReplSimulatorAsync()
  }
}

// MARK: - Reporter

/// A no-op logic-test reporter. REPL mode runs the shim's single test purely to
/// host the control socket, so the normal test-reporting events are discarded.
final class ReplNullReporter: NSObject, FBLogicXCTestReporter {
  func processWaitingForDebugger(withProcessIdentifier pid: pid_t) {}
  func didBeginExecutingTestPlan() {}
  func didFinishExecutingTestPlan() {}
  func testHadOutput(_ output: String) {}
  func handleEventJSONData(_ data: Data) {}
  func didCrashDuringTest(_ error: Error) {}
}
