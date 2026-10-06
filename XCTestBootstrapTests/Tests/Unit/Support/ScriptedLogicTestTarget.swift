/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
@testable import XCTestBootstrap

/// A logic test target that forwards everything to the local Mac, except that the shim is a fixed
/// path and every launch runs `script` under `/bin/sh` in place of the requested binary, handing it
/// the environment and output streams the strategy prepared.
final class ScriptedLogicTestTarget: NSObject, LogicTestTarget {

  private let device = MacDevice()
  private let launcher: ScriptedLauncher
  // Serial, as the real targets' main queue is: the strategies rely on work they hop onto it
  // running in submission order.
  private let serialWorkQueue = DispatchQueue(label: "com.facebook.xctestbootstrap.scripted_target")
  let xctest: ShimmedXCTest

  init(shimPath: String, script: String) {
    self.launcher = ScriptedLauncher(script: script)
    self.xctest = ShimmedXCTest(shimPath: shimPath, path: device.xctest.path)
  }

  /// What was launched through `subprocessLauncher`.
  var spawned: [Subprocess] {
    launcher.spawned
  }

  var subprocessLauncher: any SubprocessLauncher {
    launcher
  }

  func environmentAdditions() -> [String: String] {
    ["IDB_TARGET_ADDITION": "1"]
  }

  static func commands(with target: any Target) -> Self {
    fatalError("Not used by the strategies under test")
  }

  var uniqueIdentifier: String { device.uniqueIdentifier }
  var udid: String { device.udid }
  var name: String { device.name }
  var deviceType: DeviceType { device.deviceType }
  var architectures: [Architecture] { device.architectures }
  var osVersion: OSVersion { device.osVersion }
  var extendedInformation: [String: Any] { device.extendedInformation }
  var targetType: TargetType { device.targetType }
  var state: TargetState { device.state }
  func compare(_ target: any TargetInfo) -> ComparisonResult { device.compare(target) }

  var application: MacDevice { device }
  var crashLog: MacDevice { device }
  var debugServer: MacDevice { device }
  var file: MacDevice { device }
  var instruments: MacDevice { device }
  var lifecycle: MacDevice { device }
  var location: MacDevice { device }
  var log: MacDevice { device }
  var power: MacDevice { device }
  var screenshot: MacDevice { device }
  var videoRecording: MacDevice { device }
  var videoStream: MacDevice { device }
  var xctraceRecord: MacDevice { device }

  func erase() async throws { try await device.erase() }
  var logger: any ControlCoreLogger { device.logger }
  var customDeviceSetPath: String? { device.customDeviceSetPath }
  var temporaryDirectory: TemporaryDirectory { device.temporaryDirectory }
  var auxillaryDirectory: String { device.auxillaryDirectory }
  var runtimeRootDirectory: String { get async { await device.runtimeRootDirectory } }
  var platformRootDirectory: String { get async { await device.platformRootDirectory } }
  var screenInfo: TargetScreenInfo? { device.screenInfo }
  var workQueue: DispatchQueue { serialWorkQueue }
  var asyncQueue: DispatchQueue { device.asyncQueue }
  func requiresBundlesToBeSigned() -> Bool { device.requiresBundlesToBeSigned() }
  func replacementMapping() -> [String: String] { device.replacementMapping() }
}

// SAFETY: `recorded` is only read or written inside `lock`.
// patternlint-disable-next-line unchecked-sendable
private final class ScriptedLauncher: SubprocessLauncher, @unchecked Sendable {

  private let script: String
  private let lock = NSLock()
  private var recorded: [Subprocess] = []

  init(script: String) {
    self.script = script
  }

  var spawned: [Subprocess] {
    lock.withLock { recorded }
  }

  var supportsStandardInput: Bool {
    true
  }

  func spawn(_ subprocess: Subprocess, standardInput: Int32?, standardOutput: Int32?, standardError: Int32?, logger: (any ControlCoreLogger)?) async throws -> LaunchedProcess {
    lock.withLock { recorded.append(subprocess) }
    let scripted = Subprocess(executable: "/bin/sh", arguments: ["-c", script], environment: .exact(scriptEnvironment(subprocess.environment.resolved(against: ProcessInfo.processInfo.environment))), mode: subprocess.mode)
    return try await HostSubprocessLauncher().spawn(scripted, standardInput: standardInput, standardOutput: standardOutput, standardError: standardError, logger: logger)
  }
}

/// SIP strips `DYLD_*` from `/bin/sh`, but not on every host: where it survives, dyld aborts the
/// shell trying to insert the nonexistent shim before the script runs.
private func scriptEnvironment(_ environment: [String: String]) -> [String: String] {
  environment.filter { !$0.key.hasPrefix("DYLD_") }
}

struct ShimmedXCTest: XCTestExtendedCommands {

  let shimPath: String
  let path: String

  func extendedTestShim() async throws -> String {
    shimPath
  }

  func runTest(launchConfiguration: TestLaunchConfiguration, reporter: AnyObject, logger: any ControlCoreLogger) async throws {
    fatalError("Not used by the strategies under test")
  }

  func listTests(forBundleAtPath bundlePath: String, timeout: TimeInterval, withAppAtPath appPath: String?) async throws -> [String] {
    fatalError("Not used by the strategies under test")
  }

  func withTransportForTestManagerService<R>(body: (NSNumber) async throws -> R) async throws -> R {
    fatalError("Not used by the strategies under test")
  }
}
