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

/// A stand-in launcher that records the configuration production supplies.
///
/// Injected into `FBSimulatorDebuggerCommands` as its `applicationLauncher`, so the test does not
/// have to subclass a production command class or install one in the simulator's command cache.
private final class CapturingApplicationLauncher: ApplicationLaunching, @unchecked Sendable {
  private let lock = NSLock()
  private var _capturedConfiguration: FBApplicationLaunchConfiguration?

  var capturedConfiguration: FBApplicationLaunchConfiguration? {
    lock.lock()
    defer { lock.unlock() }
    return _capturedConfiguration
  }

  func launchApplication(_ configuration: FBApplicationLaunchConfiguration) async throws -> FBLaunchedApplication {
    capture(configuration)
    // Throw to unwind launchDebugServer before it reaches the
    // (process-spawning) debugServerTask path. The thrown error never
    // surfaces — tests poll the captured configuration directly.
    throw LaunchCaptureStop()
  }

  // NSLock.lock/unlock are unavailable from async contexts; scope the locking
  // in a synchronous helper instead.
  private func capture(_ configuration: FBApplicationLaunchConfiguration) {
    lock.lock()
    defer { lock.unlock() }
    _capturedConfiguration = configuration
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
    let wrapper: CapturingApplicationLauncher
  }

  /// Builds a real `FBSimulator` (with a stub device — see FBSimulatorTestSupport) and constructs
  /// the production `FBSimulatorDebuggerCommands` against it, with a capturing launcher injected.
  private func makeHarness() -> Harness {
    let simulator = FBSimulatorTestSupport.testableSimulator()
    let wrapper = CapturingApplicationLauncher()
    let commands = FBSimulatorDebuggerCommands(
      simulator: simulator,
      debugServerPath: "/fake/debugserver",
      applicationLauncher: wrapper)
    return Harness(simulator: simulator, commands: commands, wrapper: wrapper)
  }

  private func awaitCapturedConfig(_ wrapper: CapturingApplicationLauncher, timeout: TimeInterval = 1.0) -> FBApplicationLaunchConfiguration? {
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

  func testLaunchDebugServerConfiguresApplicationForDebugging() async {
    let harness = makeHarness()
    let app = FBBundleDescriptor(
      name: "MyApp",
      identifier: "com.example.myapp",
      path: "/path/to/MyApp.app",
      binary: nil)

    _ = try? await harness.commands.launchDebugServer(forHostApplication: app, port: 12345)

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

  func testLaunchDebugServerUsesApplicationDescriptorProperties() async {
    let harness = makeHarness()
    let app = FBBundleDescriptor(
      name: "SpecialApp",
      identifier: "com.example.special",
      path: "/path/to/SpecialApp.app",
      binary: nil)

    _ = try? await harness.commands.launchDebugServer(forHostApplication: app, port: 9999)

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
