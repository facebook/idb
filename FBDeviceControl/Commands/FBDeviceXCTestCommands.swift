/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation
import XCTestBootstrap

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

  // MARK: FBXCTestCommands Implementation

  @objc
  public func runTest(
    with testLaunchConfiguration: FBTestLaunchConfiguration,
    reporter: any FBXCTestReporter,
    logger: any FBControlCoreLogger
  ) -> FBFuture<NSNull> {
    // Return early and fail if there is already a test run for the device.
    // There should only ever be one test run per-device.
    if runningXcodeBuildOperation {
      return (FBDeviceControlError.describe("Cannot Start Test Manager with Configuration \(testLaunchConfiguration) as it is already running").failFuture() as! FBFuture<NSNull>)
    }
    // Terminate the reparented xcodebuild invocations.
    return FBXcodeBuildOperation.terminateAbandonedXcodebuildProcesses(forUDID: device!.udid, processFetcher: processFetcher, queue: device!.workQueue, logger: logger).onQueue(device!.workQueue) { _ in
      self.runningXcodeBuildOperation = true
      // Then start the task. This future will yield when the task has *started*.
      return self.startTestWithLaunchConfiguration(configuration: testLaunchConfiguration, logger: logger)
    }.onQueue(device!.workQueue) { (task: AnyObject) in
      // Then wrap the started task, so that we can augment it with logging and adapt it to the FBiOSTargetOperation interface.
      return FBXcodeBuildOperation.confirmExit(ofXcodebuildOperation: task as! FBSubprocess<AnyObject, AnyObject, AnyObject>, configuration: testLaunchConfiguration, reporter: reporter, target: self.device!, logger: logger)
    }.onQueue(
      device!.workQueue,
      chain: { future in
        self.runningXcodeBuildOperation = false
        return future
      }) as! FBFuture<NSNull>
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
    guard let device = device else {
      return FBDeviceControlError.describe("Device is nil").failFuture() as! FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>>
    }
    let udid = device.calls.CopyDeviceIdentifier(device.amDeviceRef)!.takeRetainedValue() as String

    // Create the Task, wrap it and store it.
    return FBXcodeBuildOperation.operation(withUDID: udid, configuration: configuration, xcodeBuildPath: xcodeBuildPath, testRunFilePath: filePath, simDeviceSet: nil, macOSTestShimPath: nil, queue: device.workQueue, logger: logger.withName("xcodebuild"))
  }
}
