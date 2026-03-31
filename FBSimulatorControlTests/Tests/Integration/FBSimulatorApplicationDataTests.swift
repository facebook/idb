/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

final class FBSimulatorApplicationDataTests: FBSimulatorControlTestCase {

  // Commented out: causes target-level timeout (too slow with other tests)
  // func testRelocatesFile() {
  //   let fixturePath = FBSimulatorControlFixtures.photo0Path()
  //   guard let simulator = assertObtainsBootedSimulator() else { return }
  //
  //   var error: NSError?
  //   var success = simulator
  //     .fileCommands(forContainerApplication: safariAppLaunch.bundleID)
  //     .onQueue(simulator.asyncQueue) { container in
  //       container.copy(fromHost: fixturePath, toContainer: "Documents")
  //     }
  //     .await(&error) != nil
  //   XCTAssertNil(error)
  //   XCTAssertTrue(success)
  //
  //   let destinationPath = (NSTemporaryDirectory() as NSString).appendingPathComponent((fixturePath as NSString).lastPathComponent)
  //   success = simulator
  //     .fileCommands(forContainerApplication: safariAppLaunch.bundleID)
  //     .onQueue(simulator.asyncQueue) { container in
  //       container.copy(fromContainer: ("Documents" as NSString).appendingPathComponent((fixturePath as NSString).lastPathComponent), toHost: destinationPath)
  //     }
  //     .await(&error) != nil
  //   XCTAssertNil(error)
  //   XCTAssertTrue(success)
  // }
}
