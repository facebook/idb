/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

// MARK: - Capturing Wrapper

/// Synthetic error used to unwind production after capturing the launch
/// configuration; tests inspect the capture, not the future result.
private struct LaunchCaptureStop: Error {}

/// Subclass of the real `FBSimulatorApplicationCommands` that overrides only
/// `launchApplicationAsync` to record the configuration supplied by the
/// production code path. All other behavior is inherited unchanged.
///
/// Registered via `simulator.commandCache.register(_:as: FBSimulatorApplicationCommands.self)`
/// so production calls to `simulator.launchApplication(...)` resolve to this
/// instance and route into the override.
private final class CapturingApplicationCommands: FBSimulatorApplicationCommands {
  private let lock = NSLock()
  private var _capturedConfiguration: FBApplicationLaunchConfiguration?

  var capturedConfiguration: FBApplicationLaunchConfiguration? {
    lock.lock()
    defer { lock.unlock() }
    return _capturedConfiguration
  }

  override func launchApplicationAsync(_ configuration: FBApplicationLaunchConfiguration) async throws -> FBLaunchedApplication {
    lock.lock()
    _capturedConfiguration = configuration
    lock.unlock()
    // Throw to unwind launchDebugServerAsync before it reaches the
    // (process-spawning) debugServerTask path. The thrown error never
    // surfaces — tests poll the captured configuration directly.
    throw LaunchCaptureStop()
  }
}

// MARK: - Tests

final class FBSimulatorDebuggerCommandsTests: XCTestCase {

  /// Holds strong references to the real `FBSimulator` and the capturing wrapper
  /// for the duration of a test. `FBSimulatorDebuggerCommands.simulator` and
  /// `FBSimulatorApplicationCommands.simulator` are both `weak`, so without an
  /// external strong ref the simulator deallocates the moment `makeCommands`
  /// returns and the production code throws "Simulator deallocated" before the
  /// override has a chance to capture.
  private struct Harness {
    let simulator: FBSimulator
    let commands: FBSimulatorDebuggerCommands
    let wrapper: CapturingApplicationCommands
  }

  /// Builds a real `FBSimulator` (with a stub device — see FBSimulatorTestSupport),
  /// pre-registers a capturing wrapper for `FBSimulatorApplicationCommands` in
  /// its command cache, and constructs the production `FBSimulatorDebuggerCommands`
  /// against that simulator.
  private func makeHarness() -> Harness {
    let simulator = FBSimulatorTestSupport.testableSimulator()
    let wrapper = CapturingApplicationCommands(simulator: simulator)
    simulator.commandCache.register(wrapper, as: FBSimulatorApplicationCommands.self)
    let commands = FBSimulatorDebuggerCommands(simulator: simulator, debugServerPath: "/fake/debugserver")
    return Harness(simulator: simulator, commands: commands, wrapper: wrapper)
  }

  private func awaitCapturedConfig(_ wrapper: CapturingApplicationCommands, timeout: TimeInterval = 1.0) -> FBApplicationLaunchConfiguration? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if let config = wrapper.capturedConfiguration {
        return config
      }
      Thread.sleep(forTimeInterval: 0.01)
    }
    return wrapper.capturedConfiguration
  }

  // MARK: - Launch Configuration

  func testLaunchDebugServerConfiguresApplicationForDebugging() {
    let harness = makeHarness()
    let app = FBBundleDescriptor(
      name: "MyApp",
      identifier: "com.example.myapp",
      path: "/path/to/MyApp.app",
      binary: nil)

    _ = harness.commands.launchDebugServer(forHostApplication: app, port: 12345)

    let config = awaitCapturedConfig(harness.wrapper)
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
    let harness = makeHarness()
    let app = FBBundleDescriptor(
      name: "SpecialApp",
      identifier: "com.example.special",
      path: "/path/to/SpecialApp.app",
      binary: nil)

    _ = harness.commands.launchDebugServer(forHostApplication: app, port: 9999)

    let config = awaitCapturedConfig(harness.wrapper)
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
