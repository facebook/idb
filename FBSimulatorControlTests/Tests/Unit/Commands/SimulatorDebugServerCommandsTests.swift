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
/// configuration; tests inspect the capture, not the launch result.
private struct LaunchCaptureStop: Error {}

/// A stand-in launcher that records the configuration production supplies.
///
/// Injected into `SimulatorDebugServerCommands` as its `applicationLauncher`, so the test does not
/// have to subclass a production command class or install one in the simulator's command cache.
private final class CapturingApplicationLauncher: ApplicationLaunching, @unchecked Sendable {
  private let lock = NSLock()
  private var _capturedConfiguration: ApplicationLaunchConfiguration?

  var capturedConfiguration: ApplicationLaunchConfiguration? {
    lock.lock()
    defer { lock.unlock() }
    return _capturedConfiguration
  }

  func launch(_ configuration: ApplicationLaunchConfiguration) async throws -> LaunchedApplication {
    capture(configuration)
    // Throw to unwind launch before it reaches the
    // (process-spawning) debugServerTask path. The thrown error never
    // surfaces — tests poll the captured configuration directly.
    throw LaunchCaptureStop()
  }

  // NSLock.lock/unlock are unavailable from async contexts; scope the locking
  // in a synchronous helper instead.
  private func capture(_ configuration: ApplicationLaunchConfiguration) {
    lock.lock()
    defer { lock.unlock() }
    _capturedConfiguration = configuration
  }
}

/// A launcher whose application "launches" at once, so production goes on to spawn the debug server.
private final class LaunchedApplicationLauncher: ApplicationLaunching, @unchecked Sendable {
  private final class Application: LaunchedApplication {
    let bundleID = "com.example.myapp"
    let processIdentifier: pid_t = 4242
    func waitForTermination() async throws {}
    func terminate() async throws {}
  }

  func launch(_ configuration: ApplicationLaunchConfiguration) async throws -> LaunchedApplication {
    Application()
  }
}

// MARK: - Tests

final class SimulatorDebugServerCommandsTests: XCTestCase {

  /// Holds strong references to the real `Simulator` and the capturing wrapper
  /// for the duration of a test. `SimulatorDebugServerCommands.simulator` and
  /// `SimulatorApplicationCommands.simulator` are both `weak`, so without an
  /// external strong ref the simulator deallocates the moment `makeCommands`
  /// returns and the production code throws "Simulator deallocated" before the
  /// override has a chance to capture.
  private struct Harness {
    let simulator: Simulator
    let commands: SimulatorDebugServerCommands
    let wrapper: CapturingApplicationLauncher
  }

  /// Builds a real `Simulator` (with a stub device — see SimulatorTestSupport) and constructs
  /// the production `SimulatorDebugServerCommands` against it, with a capturing launcher injected.
  private func makeHarness() -> Harness {
    let simulator = SimulatorTestSupport.testableSimulator()
    let wrapper = CapturingApplicationLauncher()
    let commands = SimulatorDebugServerCommands(
      simulator: simulator,
      debugServerPath: "/fake/debugserver",
      applicationLauncher: wrapper)
    return Harness(simulator: simulator, commands: commands, wrapper: wrapper)
  }

  private func awaitCapturedConfig(_ wrapper: CapturingApplicationLauncher, timeout: TimeInterval = 1.0) -> ApplicationLaunchConfiguration? {
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

  func testLaunchServerConfiguresApplicationForDebugging() async {
    let harness = makeHarness()
    let app = BundleDescriptor(
      name: "MyApp",
      identifier: "com.example.myapp",
      path: "/path/to/MyApp.app",
      binary: nil)

    _ = try? await harness.commands.launch(forHostApplication: app, port: 12345)

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

  func testLaunchServerUsesApplicationDescriptorProperties() async {
    let harness = makeHarness()
    let app = BundleDescriptor(
      name: "SpecialApp",
      identifier: "com.example.special",
      path: "/path/to/SpecialApp.app",
      binary: nil)

    _ = try? await harness.commands.launch(forHostApplication: app, port: 9999)

    let config = awaitCapturedConfig(harness.wrapper)
    XCTAssertEqual(
      config?.bundleID, "com.example.special",
      "Must use the bundle identifier from the application descriptor to launch the correct app")
    XCTAssertEqual(
      config?.bundleName, "SpecialApp",
      "Must use the bundle name from the application descriptor for display purposes")
  }

  // MARK: - The debug server process

  /// A stand-in debug server that records its arguments and pid, then waits to be signalled.
  private struct FakeDebugServer {
    struct NeverStarted: Error {}

    let directory: URL
    var executable: String { directory.appendingPathComponent("debugserver").path }
    var argumentsFile: URL { directory.appendingPathComponent("arguments") }
    var pidFile: URL { directory.appendingPathComponent("pid") }

    init(prelude: String = "") throws {
      directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let script = """
        #!/bin/sh
        \(prelude)
        echo "$@" > '\(directory.appendingPathComponent("arguments").path)'
        echo $$ > '\(directory.appendingPathComponent("pid").path)'
        while :; do sleep 1; done
        """
      try script.write(toFile: executable, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable)
    }

    func awaitProcessIdentifier() throws -> pid_t {
      let deadline = Date().addingTimeInterval(10)
      while Date() < deadline {
        if let contents = try? String(contentsOf: pidFile, encoding: .utf8), let pid = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)) {
          return pid
        }
        Thread.sleep(forTimeInterval: 0.02)
      }
      throw NeverStarted()
    }
  }

  private func isDead(_ processIdentifier: pid_t, within seconds: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
      if kill(processIdentifier, 0) != 0 {
        return true
      }
      Thread.sleep(forTimeInterval: 0.02)
    }
    return false
  }

  private func launch(_ fake: FakeDebugServer, port: in_port_t) async throws -> (any DebugServer, Simulator) {
    let simulator = SimulatorTestSupport.testableSimulator()
    let commands = SimulatorDebugServerCommands(
      simulator: simulator,
      debugServerPath: fake.executable,
      applicationLauncher: LaunchedApplicationLauncher())
    let app = BundleDescriptor(name: "MyApp", identifier: "com.example.myapp", path: "/path/to/MyApp.app", binary: nil)
    return (try await commands.launch(forHostApplication: app, port: port), simulator)
  }

  func testLaunchAttachesTheDebugServerToTheLaunchedApplication() async throws {
    let fake = try FakeDebugServer()
    let (server, simulator) = try await launch(fake, port: 12345)
    let processIdentifier = try fake.awaitProcessIdentifier()

    XCTAssertEqual(server.lldbBootstrapCommands, ["process connect connect://localhost:12345"])
    XCTAssertEqual(
      try String(contentsOf: fake.argumentsFile, encoding: .utf8), "localhost:12345 --attach 4242\n")

    try await server.cancel()
    XCTAssertTrue(isDead(processIdentifier, within: 5))
    withExtendedLifetime(simulator) {}
  }

  func testCancelKillsADebugServerThatIgnoresSIGTERM() async throws {
    let fake = try FakeDebugServer(prelude: "trap '' TERM")
    let (server, simulator) = try await launch(fake, port: 12346)
    let processIdentifier = try fake.awaitProcessIdentifier()

    try await server.cancel()

    XCTAssertTrue(isDead(processIdentifier, within: 5), "SIGKILL follows SIGTERM after the grace period")
    withExtendedLifetime(simulator) {}
  }

  // MARK: - Path Construction

  func testDebugServerPathCombinesXcodeContentsDirectoryWithLLDBRelativePath() {
    let path = SimulatorDebugServerCommands.resolveDebugServerPath()
    let contentsDirectory = XcodeConfiguration.contentsDirectory
    let expectedPath = (contentsDirectory as NSString)
      .appendingPathComponent("SharedFrameworks/LLDB.framework/Resources/debugserver")
    XCTAssertEqual(
      path, expectedPath,
      "debugServerPath must combine Xcode Contents directory with LLDB debugserver relative path to locate the binary correctly")
  }
}
