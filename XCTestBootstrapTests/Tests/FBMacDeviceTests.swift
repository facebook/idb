/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import XCTest
import XCTestBootstrap

final class FBMacDeviceTests: XCTestCase {

  var device: FBMacDevice!
  var installedApp: FBInstalledApplication!
  var tempInstallDir: String?

  override func setUp() {
    super.setUp()
    device = FBMacDevice()

    let descriptor: FBBundleDescriptor
    do {
      descriptor = try FBMacDeviceTests.macCommonApplication()
    } catch {
      preconditionFailure("Failed to load MacCommonApp fixture: \(error)")
    }

    // Copy the .app to a temporary directory so that uninstall (which deletes the
    // installed path) does not destroy the fixture inside the test bundle.
    tempInstallDir = NSTemporaryDirectory().appendingFormat("%@", UUID().uuidString)
    let tempDir = tempInstallDir!
    do {
      try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true, attributes: nil)
    } catch {
      preconditionFailure("Failed to create temp dir: \(error)")
    }
    let destPath = (tempDir as NSString).appendingPathComponent((descriptor.path as NSString).lastPathComponent)
    do {
      try FileManager.default.copyItem(atPath: descriptor.path, toPath: destPath)
    } catch {
      preconditionFailure("Failed to copy fixture app: \(error)")
    }

    do {
      installedApp = try device.installApplication(withPath: destPath).await(withTimeout: 5)
    } catch {
      preconditionFailure("Failed to install dummy app: \(error)")
    }
  }

  override func tearDownWithError() throws {
    var teardownError: Error?
    do {
      try device.restorePrimaryDeviceState().await(withTimeout: 5)
    } catch {
      teardownError = error
      NSLog("Failed to tearDown test gracefully %@. Further tests may be affected", error.localizedDescription)
    }
    if let tempDir = tempInstallDir {
      try? FileManager.default.removeItem(atPath: tempDir)
      tempInstallDir = nil
    }
    if let err = teardownError {
      throw err
    }
  }

  func testMacComparsion() {
    let anotherDevice = FBMacDevice()
    let comparsionResult = device.compare(anotherDevice)

    XCTAssertEqual(
      comparsionResult,
      .orderedSame,
      "We should have only one exemplar of FBMacDevice, so this is same"
    )
  }

  func testMacStateRestorationWithEmptyTasks() {
    XCTAssertNotNil(
      device.restorePrimaryDeviceState().result,
      "State restoration without launched task should complete immidiately"
    )
  }

  func testInstallNotExistedApplicationAtPath() {
    let installTask = device.installApplication(withPath: "/not/existed/path")
    XCTAssertNotNil(
      installTask.error,
      "Installing not existed app should fail immidiately"
    )
  }

  func testInstallExistedApplicationAtPath() {
    XCTAssertTrue(
      installedApp.bundle.identifier == "com.facebook.MacCommonApp",
      "Dummy application should install properly"
    )
  }

  func testUninstallApplicationByIncorrectBundleID() {
    XCTAssertNotNil(device.uninstallApplication(withBundleID: "not.existed").error)
  }

  func testLaunchingNotInstalledAppByBuntleID() {
    let config = FBApplicationLaunchConfiguration(
      bundleID: "not.existed",
      bundleName: "not.existed",
      arguments: [],
      environment: [:],
      waitForDebugger: false,
      io: FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull(),
      launchMode: .relaunchIfRunning
    )
    let launchAppFuture = device.launchApplication(config)

    XCTAssertNotNil(
      launchAppFuture.error,
      "Launhing not existed app should fail immidiately"
    )
  }

  func testLaunchingExistedApp() throws {
    let config = FBApplicationLaunchConfiguration(
      bundleID: installedApp.bundle.identifier,
      bundleName: installedApp.bundle.name,
      arguments: [],
      environment: [:],
      waitForDebugger: false,
      io: FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull(),
      launchMode: .relaunchIfRunning
    )

    try device.launchApplication(config).await(withTimeout: 5)
  }
}
