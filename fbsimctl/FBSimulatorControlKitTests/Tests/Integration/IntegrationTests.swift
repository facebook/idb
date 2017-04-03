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
    let set1 = URL.urlRelativeTo(NSTemporaryDirectory(), component: "FBSimulatorControlKitTests/set_1", isDirectory: true)
    let set2 = URL.urlRelativeTo(NSTemporaryDirectory(), component: "FBSimulatorControlKitTests/set_2", isDirectory: true)

    if ((try? FileManager.default.createDirectory(at: set1, withIntermediateDirectories: true, attributes: [:])) == nil) {
      XCTFail("Could not create directory at \(set1)")
    }
    if ((try? FileManager.default.createDirectory(at: set2, withIntermediateDirectories: true, attributes: [:])) == nil) {
      XCTFail("Could not create directory at \(set2)")
    }

    self.assertCLIRunsSuccessfully(set1, ["delete"])
    self.assertCLIRunsSuccessfully(set2, ["delete"])
    self.assertCLIRunsSuccessfully(set1, ["create", "iPhone 5s"])
    self.assertCLIRunsSuccessfully(set2, ["create", "iPad Air 2"])
    self.assertCLIRunsSuccessfully(set1, ["iPhone 5s", "boot"])
    self.assertCLIRunsSuccessfully(set2, ["iPad Air 2", "boot"])
    XCTAssertEqual(
      self.assertCLIRunsSuccessfully(set1, ["list_device_sets"]).count,
      2
    )
    self.assertCLIRunsSuccessfully(set1, ["delete"])
    XCTAssertEqual(
      self.assertCLIRunsSuccessfully(set2, ["--format", "%m%s", "list"]),
      ["iPad Air 2 | Booted"]
    )
    self.assertCLIRunsSuccessfully(set2, ["shutdown"])
    XCTAssertEqual(
      self.assertCLIRunsSuccessfully(set2, ["--format", "%m%s", "list"]),
      ["iPad Air 2 | Shutdown"]
    )
    self.assertCLIRunsSuccessfully(set2, ["delete"])
  }

  @discardableResult
  func assertCLIRunsSuccessfully(_ simulatorSet: URL, _ command: [String]) -> [String] {
    let arguments = ["--set", simulatorSet.path, "--simulators"] + command
    return self.assertCLIRunsSuccessfully(arguments)
  }
}
