/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

// MARK: - Simulator Test Double

private class SimulatorDouble: NSObject {
  let workQueue = DispatchQueue(label: "com.test.debugger.workQueue")
  var capturedLaunchConfiguration: FBApplicationLaunchConfiguration?
  let launchFuture = FBMutableFuture<FBLaunchedApplication>()

  @objc(launchApplication:)
  func launchApplication(_ configuration: FBApplicationLaunchConfiguration) -> FBFuture<FBLaunchedApplication> {
    capturedLaunchConfiguration = configuration
    return unsafeBitCast(launchFuture, to: FBFuture<FBLaunchedApplication>.self)
  }
}

// MARK: - Tests

final class FBSimulatorDebuggerCommandsTests: XCTestCase {

  private func makeCommands(simulatorDouble: SimulatorDouble) -> FBSimulatorDebuggerCommands {
    let castedSim = unsafeBitCast(simulatorDouble, to: FBSimulator.self)
    return FBSimulatorDebuggerCommands(simulator: castedSim, debugServerPath: "/fake/debugserver")
  }

  private func awaitCapturedConfig(_ double: SimulatorDouble, timeout: TimeInterval = 1.0) -> FBApplicationLaunchConfiguration? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if let config = double.capturedLaunchConfiguration {
        return config
      }
      Thread.sleep(forTimeInterval: 0.01)
    }
    return double.capturedLaunchConfiguration
  }

  // MARK: - Launch Configuration

  func testLaunchDebugServerConfiguresApplicationForDebugging() {
    let simulatorDouble = SimulatorDouble()
    let commands = makeCommands(simulatorDouble: simulatorDouble)
    let app = FBBundleDescriptor(
      name: "MyApp",
      identifier: "com.example.myapp",
      path: "/path/to/MyApp.app",
      binary: nil)

    _ = commands.launchDebugServer(forHostApplication: app, port: 12345)

    let config = awaitCapturedConfig(simulatorDouble)
    XCTAssertNotNil(config, "Should have captured the launch configuration")
    XCTAssertTrue(
      config?.waitForDebugger ?? false,
      "Must launch with waitForDebugger=YES so the debugger can attach before execution begins")
    XCTAssertEqual(
      config?.launchMode, .failIfRunning,
      "Must use FailIfRunning to prevent attaching to an already-running app instance")
    XCTAssertEqual(
      config?.arguments ?? ["unset"], [],
      "No custom arguments should be passed to the debugged application")
    XCTAssertEqual(
      config?.environment ?? ["unset": "unset"], [:],
      "No custom environment variables should be passed to the debugged application")
  }

  func testLaunchDebugServerUsesApplicationDescriptorProperties() {
    let simulatorDouble = SimulatorDouble()
    let commands = makeCommands(simulatorDouble: simulatorDouble)
    let app = FBBundleDescriptor(
      name: "SpecialApp",
      identifier: "com.example.special",
      path: "/path/to/SpecialApp.app",
      binary: nil)

    _ = commands.launchDebugServer(forHostApplication: app, port: 9999)

    let config = awaitCapturedConfig(simulatorDouble)
    XCTAssertEqual(
      config?.bundleID, "com.example.special",
      "Must use the bundle identifier from the application descriptor to launch the correct app")
    XCTAssertEqual(
      config?.bundleName, "SpecialApp",
      "Must use the bundle name from the application descriptor for display purposes")
  }

  // MARK: - Path Construction

  func testDebugServerPathCombinesXcodeContentsDirectoryWithLLDBRelativePath() {
    let path = FBSimulatorDebuggerCommands.resolveDebugServerPath()
    let contentsDirectory = FBXcodeConfiguration.contentsDirectory
    let expectedPath = (contentsDirectory as NSString)
      .appendingPathComponent("SharedFrameworks/LLDB.framework/Resources/debugserver")
    XCTAssertEqual(
      path, expectedPath,
      "debugServerPath must combine Xcode Contents directory with LLDB debugserver relative path to locate the binary correctly")
  }
}
