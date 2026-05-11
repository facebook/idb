/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation
import XCTestBootstrap

// swiftlint:disable force_cast

@objc(FBDeviceXCTestCommands)
public class FBDeviceXCTestCommands: NSObject, FBXCTestCommands, FBiOSTargetCommand {
  private(set) weak var device: FBDevice?
  private(set) var workingDirectory: String
  private(set) var processFetcher: FBProcessFetcher
  var runningXcodeBuildOperation = false

  // MARK: Initializers

  @objc
  public class func commands(with target: any FBiOSTarget) -> Self {
    return unsafeDowncast(FBDeviceXCTestCommands(device: target as! FBDevice, workingDirectory: NSTemporaryDirectory()), to: self)
  }

  init(device: FBDevice, workingDirectory: String) {
    self.device = device
    self.workingDirectory = workingDirectory
    self.processFetcher = FBProcessFetcher()
    super.init()
  }

  // MARK: FBXCTestCommands (legacy FBFuture entry point)

  @objc(runTestWithLaunchConfiguration:reporter:logger:)
  public func runTest(
    withLaunchConfiguration testLaunchConfiguration: FBTestLaunchConfiguration,
    reporter: AnyObject,
    logger: any FBControlCoreLogger
  ) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await runTestAsync(withLaunchConfiguration: testLaunchConfiguration, reporter: reporter, logger: logger)
      return NSNull()
    }
  }

  // MARK: - Async

  fileprivate func runTestAsync(
    withLaunchConfiguration testLaunchConfiguration: FBTestLaunchConfiguration,
    reporter: AnyObject,
    logger: any FBControlCoreLogger
  ) async throws {
    if runningXcodeBuildOperation {
      throw FBDeviceControlError.describe("Cannot Start Test Manager with Configuration \(testLaunchConfiguration) as it is already running").build()
    }
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    runningXcodeBuildOperation = true
    defer { runningXcodeBuildOperation = false }

    _ = try await bridgeFBFuture(FBXcodeBuildOperation.terminateAbandonedXcodebuildProcesses(forUDID: device.udid, processFetcher: processFetcher, queue: device.workQueue, logger: logger))
    let task = try await bridgeFBFuture(startTestWithLaunchConfiguration(configuration: testLaunchConfiguration, logger: logger))
    try await bridgeFBFutureVoid(FBXcodeBuildOperation.confirmExit(ofXcodebuildOperation: task, configuration: testLaunchConfiguration, reporter: reporter as! FBXCTestReporter, target: device, logger: logger))
  }

  // MARK: Private

  private func startTestWithLaunchConfiguration(configuration: FBTestLaunchConfiguration, logger: any FBControlCoreLogger) -> FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>> {
    // Create the .xctestrun file
    let filePath: String
    do {
      filePath = try FBXcodeBuildOperation.createXCTestRunFile(at: workingDirectory, fromConfiguration: configuration)
    } catch {
      return FBDeviceControlError.describe("Failed to create xctestrun file: \(error)").failFuture() as! FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>>
    }
    // Find the path to xcodebuild
    let xcodeBuildPath: String
    do {
      xcodeBuildPath = try FBXcodeBuildOperation.xcodeBuildPath()
    } catch {
      return FBDeviceControlError.describe("Failed to find xcodebuild: \(error)").failFuture() as! FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>>
    }
    // This is to walk around a bug in xcodebuild. The UDID inside xcodebuild does not match
    // UDID reported by device properties (the difference is missing hyphen in xcodebuild).
    // This results in xcodebuild returning an error, since it cannot find a device with requested
    // id (e.g. we query for 00008101-001D296A2EE8001E, while xcodebuild have
    // 00008101001D296A2EE8001E).
    guard let device else {
      return FBDeviceControlError.describe("Device is nil").failFuture() as! FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>>
    }
    let udid = device.calls.CopyDeviceIdentifier(device.amDeviceRef)!.takeRetainedValue() as String

    // Create the Task, wrap it and store it.
    return FBXcodeBuildOperation.operation(withUDID: udid, configuration: configuration, xcodeBuildPath: xcodeBuildPath, testRunFilePath: filePath, simDeviceSet: nil, macOSTestShimPath: nil, queue: device.workQueue, logger: logger.withName("xcodebuild"))
  }
}

// MARK: - AsyncXCTestCommands

extension FBDeviceXCTestCommands: AsyncXCTestCommands {

  public func runTest(
    launchConfiguration: FBTestLaunchConfiguration,
    reporter: AnyObject,
    logger: any FBControlCoreLogger
  ) async throws {
    try await runTestAsync(withLaunchConfiguration: launchConfiguration, reporter: reporter, logger: logger)
  }
}

// MARK: - FBDevice+AsyncXCTestCommands

extension FBDevice: AsyncXCTestCommands {

  public func runTest(
    launchConfiguration: FBTestLaunchConfiguration,
    reporter: AnyObject,
    logger: any FBControlCoreLogger
  ) async throws {
    try await xctestCommands().runTest(launchConfiguration: launchConfiguration, reporter: reporter, logger: logger)
  }
}
