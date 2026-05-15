/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

final class FBSimulatorCrashLogTests: FBSimulatorControlTestCase {

  // Commented out: causes target-level timeout (too slow with other tests)
  // func testAppCrashLogIsFetched() {
  //   if FBSimulatorControlTestCase.isRunningOnTravis() {
  //     return
  //   }
  //
  //   guard let simulator = assertObtainsBootedSimulator(withInstalledApplication: tableSearchApplication) else { return }
  //   let path = Bundle(for: type(of: self)).path(forResource: "libShimulator", ofType: "dylib")!
  //   var appLaunch = tableSearchAppLaunch
  //   var environment = appLaunch.environment as! [String: String]
  //   environment["SHIMULATOR_CRASH_AFTER"] = "1"
  //   environment["DYLD_INSERT_LIBRARIES"] = path
  //   let modifiedLaunch = FBApplicationLaunchConfiguration(
  //     bundleID: appLaunch.bundleID,
  //     bundleName: appLaunch.bundleName,
  //     arguments: appLaunch.arguments,
  //     environment: environment,
  //     waitForDebugger: false,
  //     io: appLaunch.io,
  //     launchMode: appLaunch.launchMode
  //   )
  //
  //   let crashLogFuture = simulator.notifyOfCrash(FBCrashLogInfo.predicate(forIdentifier: "TableSearch"))
  //
  //   var error: NSError?
  //   var success = simulator.launchApplication(modifiedLaunch).await(&error) != nil
  //   XCTAssertNil(error)
  //   XCTAssertTrue(success)
  //
  //   let crashLog = crashLogFuture.await(withTimeout: FBControlCoreGlobalConfiguration.slowTimeout, error: &error)
  //   XCTAssertNil(error)
  //   XCTAssertNotNil(crashLog)
  //   XCTAssertEqual(crashLog?.identifier, "TableSearch")
  //   XCTAssertTrue(try! String(contentsOfFile: crashLog!.crashPath, encoding: .utf8).contains("\"app_name\":\"TableSearch\""))
  // }
}
