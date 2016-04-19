/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

import XCTest
import FBSimulatorControl
@testable import FBSimulatorControlKit

class IntegrationTests : XCTestCase {
  func testNoInterferenceBeetweenDeviceSets() {
    let set1 = self.temporaryDirectory().URLByAppendingPathComponent("set_1", isDirectory: true)
    let set2 = self.temporaryDirectory().URLByAppendingPathComponent("set_2", isDirectory: true)

    if ((try? NSFileManager.defaultManager().createDirectoryAtURL(set1, withIntermediateDirectories: true, attributes: [:])) == nil) {
      XCTFail("Could not create directory at \(set1)")
    }
    if ((try? NSFileManager.defaultManager().createDirectoryAtURL(set2, withIntermediateDirectories: true, attributes: [:])) == nil) {
      XCTFail("Could not create directory at \(set2)")
    }

    self.assertCLIRunsSuccessfully(["--set", set1.path!, "all", "delete"])
    self.assertCLIRunsSuccessfully(["--set", set2.path!, "all", "delete"])
    self.assertCLIRunsSuccessfully(["--set", set1.path!, "create", "iPhone 5s"])
    self.assertCLIRunsSuccessfully(["--set", set2.path!, "create", "iPad 2"])
    self.assertCLIRunsSuccessfully(["--set", set1.path!, "iPhone 5s", "boot"])
    self.assertCLIRunsSuccessfully(["--set", set2.path!, "iPad 2", "boot"])
    self.assertCLIRunsSuccessfully(["--set", set1.path!, "all", "delete"])
    XCTAssertEqual(
      self.assertCLIRunsSuccessfully(["--set", set2.path!, "--device-name", "--state", "list"]),
      ["\'iPad 2\' Booted"]
    )
    self.assertCLIRunsSuccessfully(["--set", set2.path!, "all", "shutdown"])
    XCTAssertEqual(
      self.assertCLIRunsSuccessfully(["--set", set2.path!, "--device-name", "--state", "list"]),
      ["\'iPad 2\' Shutdown"]
    )
    self.assertCLIRunsSuccessfully(["--set", set2.path!, "all", "delete"])
  }
}
