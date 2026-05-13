/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore

/// A stub implementation of FBiOSTarget for testing.
final class FBiOSTargetDouble: NSObject, FBiOSTarget {

  // MARK: FBiOSTargetInfo - writable properties for test configuration

  var uniqueIdentifier: String = ""
  var udid: String = ""
  var name: String = ""
  var auxillaryDirectory: String = ""
  var customDeviceSetPath: String?
  var state: FBiOSTargetState = .unknown
  var targetType: FBiOSTargetType = .simulator
  var deviceType: FBDeviceType!
  var osVersion: FBOSVersion!

  // MARK: FBiOSTarget - synthesized properties

  var architectures: [FBArchitecture] = []
  var logger: (any FBControlCoreLogger)?
  var platformRootDirectory: String = ""
  var runtimeRootDirectory: String = ""
  var screenInfo: FBiOSTargetScreenInfo?
  var temporaryDirectory: FBTemporaryDirectory!

  // MARK: FBiOSTargetCommand

  @objc(commandsWithTarget:)
  static func commands(with target: any FBiOSTarget) -> Self {
    return self.init()
  }

  // MARK: FBiOSTarget

  var workQueue: DispatchQueue { .main }

  var asyncQueue: DispatchQueue { .global(qos: .userInitiated) }

  @objc(compare:)
  func compare(_ target: any FBiOSTarget) -> ComparisonResult {
    return FBiOSTargetComparison(self, target)
  }

  var extendedInformation: [String: Any] { [:] }

  func requiresBundlesToBeSigned() -> Bool { false }

  func replacementMapping() -> [String: String] { [:] }

  func environmentAdditions() -> [String: String] { [:] }

  // MARK: FBApplicationCommands

  func installApplication(withPath path: String) -> FBFuture<FBInstalledApplication> {
    return FBFuture(error: FBControlCoreError.describe("Unimplemented").build())
  }

  func uninstallApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    return FBFuture(error: FBControlCoreError.describe("Unimplemented").build())
  }

  func launchApplication(_ configuration: FBApplicationLaunchConfiguration) -> FBFuture<FBLaunchedApplication> {
    return FBFuture(error: FBControlCoreError.describe("Unimplemented").build())
  }

  func killApplication(withBundleID bundleID: String) -> FBFuture<NSNull> {
    return FBFuture(error: FBControlCoreError.describe("Unimplemented").build())
  }

  func installedApplications() -> FBFuture<NSArray> {
    return FBFuture(error: FBControlCoreError.describe("Unimplemented").build())
  }

  func installedApplication(withBundleID bundleID: String) -> FBFuture<FBInstalledApplication> {
    return FBFuture(error: FBControlCoreError.describe("Unimplemented").build())
  }

  func processID(withBundleID bundleID: String) -> FBFuture<NSNumber> {
    return FBFuture(error: FBControlCoreError.describe("Unimplemented").build())
  }

  // MARK: FBCrashLogCommands

  func notifyOfCrash(_ predicate: NSPredicate) -> FBFuture<FBCrashLogInfo> {
    return FBFuture(error: FBControlCoreError.describe("Unimplemented").build())
  }

  // MARK: FBVideoRecordingCommands

  func startRecording(toFile filePath: String) -> FBFuture<FBiOSTargetOperation> {
    return FBFuture(error: FBControlCoreError.describe("Unimplemented").build())
  }

  func stopRecording() -> FBFuture<NSNull> {
    return FBFuture(error: FBControlCoreError.describe("Unimplemented").build())
  }

  // MARK: FBXCTestCommands

  func runTest(withLaunchConfiguration testLaunchConfiguration: FBTestLaunchConfiguration, reporter: AnyObject, logger: any FBControlCoreLogger) -> FBFuture<NSNull> {
    return FBFuture(error: FBControlCoreError.describe("Unimplemented").build())
  }

  // MARK: FBXCTraceRecordCommandsProtocol

  func startXctraceRecord(_ configuration: FBXCTraceRecordConfiguration, logger: any FBControlCoreLogger) -> FBFuture<FBXCTraceRecordOperation> {
    return FBFuture(error: FBControlCoreError.describe("Unimplemented").build())
  }

  // MARK: FBInstrumentsCommandsProtocol

  func startInstruments(_ configuration: FBInstrumentsConfiguration, logger: any FBControlCoreLogger) -> FBFuture<FBInstrumentsOperation> {
    return FBFuture(error: FBControlCoreError.describe("Unimplemented").build())
  }

}
