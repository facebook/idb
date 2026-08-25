/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

private let DeviceSetEnvKey = "FBSIMULATORCONTROL_DEVICE_SET"
private let DeviceSetEnvDefault = "default"

private let LaunchTypeEnvKey = "FBSIMULATORCONTROL_LAUNCH_TYPE"
private let LaunchTypeSimulatorApp = "simulator_app"
private let LaunchTypeDirect = "direct"

private let RecordVideoEnvKey = "FBSIMULATORCONTROL_RECORD_VIDEO"

/// A Test Case that bootstraps a FBSimulatorControl instance.
/// Should be overridden to provide Integration tests for Simulators.
class FBSimulatorControlTestCase: XCTestCase {

  var simulatorConfiguration: FBSimulatorConfiguration!
  var bootConfiguration: FBSimulatorBootConfiguration!
  var deviceSetPath: String?

  private var _control: FBSimulatorControl?
  var control: FBSimulatorControl {
    if _control == nil {
      let noLogger: (any FBControlCoreLogger)? = nil
      let configuration = FBSimulatorControlConfiguration(
        deviceSetPath: deviceSetPath,
        logger: noLogger
      )
      do {
        _control = try FBSimulatorControl.withConfiguration(configuration)
      } catch {
        XCTFail("Failed to create FBSimulatorControl: \(error)")
      }
    }
    return _control!
  }

  override class func setUp() {
    super.setUp()
    if ProcessInfo.processInfo.environment[FBControlCoreStderrLogging] == nil {
      setenv(FBControlCoreStderrLogging, "YES", 1)
    }
    if ProcessInfo.processInfo.environment[FBControlCoreDebugLogging] == nil {
      setenv(FBControlCoreDebugLogging, "NO", 1)
    }
    FBControlCoreGlobalConfiguration.defaultLogger.log("Current Configuration => \(String(describing: FBControlCoreGlobalConfiguration.description))")
  }

  class var isRunningOnTravis: Bool {
    if ProcessInfo.processInfo.environment["TRAVIS"] != nil {
      NSLog("Running in Travis environment, skipping test")
      return true
    }
    return false
  }

  class var useDirectLaunching: Bool {
    return ProcessInfo.processInfo.environment[LaunchTypeEnvKey] != LaunchTypeSimulatorApp
  }

  class var bootOptions: FBSimulatorBootOptions {
    var options: FBSimulatorBootOptions = []
    if useDirectLaunching {
      options.insert(.tieToProcessLifecycle)
    }
    return options
  }

  class var defaultDeviceSetPath: String? {
    // Tests use an isolated device set unless explicitly opted into the default
    // set: the default set holds the developer's own simulators, and suite
    // tearDown shuts down every booted device in whichever set is used.
    let value = ProcessInfo.processInfo.environment[DeviceSetEnvKey]
    if value == DeviceSetEnvDefault {
      return nil
    }
    return (NSTemporaryDirectory() as NSString).appendingPathComponent("FBSimulatorControlSimulatorLaunchTests_CustomSet")
  }

  class var defaultBootConfiguration: FBSimulatorBootConfiguration {
    return FBSimulatorBootConfiguration(options: bootOptions, environment: [:])
  }

  override func setUpWithError() throws {
    continueAfterFailure = false
    // Memoized: a no-op after the first test's load. Throwing here turns a load failure into a
    // per-test failure instead of killing the runner.
    try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(FBControlCoreGlobalConfiguration.defaultLogger)
    simulatorConfiguration = try FBSimulatorConfiguration.defaultConfiguration().withDeviceModel(.modeliPhone16)
    bootConfiguration = FBSimulatorBootConfiguration(options: FBSimulatorControlTestCase.bootOptions, environment: [:])
    deviceSetPath = FBSimulatorControlTestCase.defaultDeviceSetPath
  }

  override func tearDown() async throws {
    // `control` is lazy: referencing it here would bootstrap FBSimulatorControl —
    // and shut down every booted simulator in the device set — for tests that
    // never touched a simulator. Only clean up if the test actually used it.
    if let control = _control {
      _ = try? await bridgeFBFuture(control.set.shutdownAll())
    }
    _control = nil
  }
}
