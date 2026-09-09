/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation
import XCTestBootstrap

public enum FBDeviceXCTestError: Error {
  case testManagerAlreadyRunning(configurationDescription: String)
  case unexpectedReporter(reporterDescription: String)
  case xctestrunCreationFailed(underlying: Error)
  case xcodebuildNotFound(underlying: Error)
  case deviceIdentifierUnavailable(deviceDescription: String)
}

extension FBDeviceXCTestError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .testManagerAlreadyRunning(configurationDescription):
      return "Cannot Start Test Manager with Configuration \(configurationDescription) as it is already running"
    case let .unexpectedReporter(reporterDescription):
      return "\(reporterDescription) is not an FBXCTestReporter"
    case let .xctestrunCreationFailed(underlying):
      return "Failed to create xctestrun file: \(underlying)"
    case let .xcodebuildNotFound(underlying):
      return "Failed to find xcodebuild: \(underlying)"
    case let .deviceIdentifierUnavailable(deviceDescription):
      return "No device identifier could be copied from \(deviceDescription)"
    }
  }
}

public final class FBDeviceXCTestCommands {
  private(set) weak var device: FBDevice?
  private(set) var workingDirectory: String
  private(set) var processFetcher: FBProcessFetcher
  var runningXcodeBuildOperation = false

  public class func commands(with device: FBDevice) -> FBDeviceXCTestCommands {
    FBDeviceXCTestCommands(device: device, workingDirectory: NSTemporaryDirectory())
  }

  init(device: FBDevice, workingDirectory: String) {
    self.device = device
    self.workingDirectory = workingDirectory
    self.processFetcher = FBProcessFetcher()
  }

  // MARK: - Async

  fileprivate func runTest(
    withLaunchConfiguration testLaunchConfiguration: FBTestLaunchConfiguration,
    reporter: AnyObject,
    logger: any FBControlCoreLogger
  ) async throws {
    if runningXcodeBuildOperation {
      throw FBDeviceXCTestError.testManagerAlreadyRunning(configurationDescription: String(describing: testLaunchConfiguration))
    }
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    guard let reporter = reporter as? FBXCTestReporter else {
      throw FBDeviceXCTestError.unexpectedReporter(reporterDescription: String(describing: reporter))
    }
    runningXcodeBuildOperation = true
    defer { runningXcodeBuildOperation = false }

    _ = try await bridgeFBFuture(FBXcodeBuildOperation.terminateAbandonedXcodebuildProcesses(forUDID: device.udid, processFetcher: processFetcher, queue: device.workQueue, logger: logger))
    let task = try await bridgeFBFuture(startTestWithLaunchConfiguration(configuration: testLaunchConfiguration, logger: logger))
    try await bridgeFBFutureVoid(FBXcodeBuildOperation.confirmExit(ofXcodebuildOperation: task, configuration: testLaunchConfiguration, reporter: reporter, target: device, logger: logger))
  }

  private func startTestWithLaunchConfiguration(configuration: FBTestLaunchConfiguration, logger: any FBControlCoreLogger) throws -> FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>> {
    let filePath: String
    do {
      filePath = try FBXcodeBuildOperation.createXCTestRunFile(at: workingDirectory, fromConfiguration: configuration)
    } catch {
      throw FBDeviceXCTestError.xctestrunCreationFailed(underlying: error)
    }
    let xcodeBuildPath: String
    do {
      xcodeBuildPath = try FBXcodeBuildOperation.xcodeBuildPath()
    } catch {
      throw FBDeviceXCTestError.xcodebuildNotFound(underlying: error)
    }
    // This is to work around a bug in xcodebuild. The UDID inside xcodebuild does not match
    // UDID reported by device properties (the difference is missing hyphen in xcodebuild).
    // This results in xcodebuild returning an error, since it cannot find a device with requested
    // id (e.g. we query for 00008101-001D296A2EE8001E, while xcodebuild have
    // 00008101001D296A2EE8001E).
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    guard let identifier = device.calls.CopyDeviceIdentifier(device.amDeviceRef) else {
      throw FBDeviceXCTestError.deviceIdentifierUnavailable(deviceDescription: String(describing: device))
    }
    let udid = identifier.takeRetainedValue() as String

    return FBXcodeBuildOperation.operation(withUDID: udid, configuration: configuration, xcodeBuildPath: xcodeBuildPath, testRunFilePath: filePath, simDeviceSet: nil, macOSTestShimPath: nil, queue: device.workQueue, logger: logger.withName("xcodebuild"))
  }
}

// MARK: - FBDevice+XCTestCommands

extension FBDevice: XCTestCommands {

  public func runTest(
    launchConfiguration: FBTestLaunchConfiguration,
    reporter: AnyObject,
    logger: any FBControlCoreLogger
  ) async throws {
    try await xctest.runTest(withLaunchConfiguration: launchConfiguration, reporter: reporter, logger: logger)
  }
}
