/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
@testable import FBSimulatorControlKit
import Foundation
import XCTest

class IntegrationTests: XCTestCase {
  func testNoInterferenceBeetweenDeviceSets() {
    let set1 = URL.urlRelativeTo(NSTemporaryDirectory(), component: "FBSimulatorControlKitTests/set_1", isDirectory: true)
    let set2 = URL.urlRelativeTo(NSTemporaryDirectory(), component: "FBSimulatorControlKitTests/set_2", isDirectory: true)

    if (try? FileManager.default.createDirectory(at: set1, withIntermediateDirectories: true, attributes: [:])) == nil {
      XCTFail("Could not create directory at \(set1)")
    }
    if (try? FileManager.default.createDirectory(at: set2, withIntermediateDirectories: true, attributes: [:])) == nil {
      XCTFail("Could not create directory at \(set2)")
    }

    assertCLIRunsSuccessfully(set1, ["delete"])
    assertCLIRunsSuccessfully(set2, ["delete"])
    assertCLIRunsSuccessfully(set1, ["create", "iPhone 5s"])
    assertCLIRunsSuccessfully(set2, ["create", "iPad Air 2"])
    assertCLIRunsSuccessfully(set1, ["iPhone 5s", "boot"])
    assertCLIRunsSuccessfully(set2, ["iPad Air 2", "boot"])
    XCTAssertEqual(
      assertCLIRunsSuccessfully(set1, ["list_device_sets"]).count,
      2
    )
    assertCLIRunsSuccessfully(set1, ["delete"])
    XCTAssertEqual(
      assertCLIRunsSuccessfully(set2, ["--format", "%m%s", "list"]),
      ["iPad Air 2 | Booted"]
    )
    assertCLIRunsSuccessfully(set2, ["shutdown"])
    XCTAssertEqual(
      assertCLIRunsSuccessfully(set2, ["--format", "%m%s", "list"]),
      ["iPad Air 2 | Shutdown"]
    )
    assertCLIRunsSuccessfully(set2, ["delete"])
  }

  @discardableResult
  func assertCLIRunsSuccessfully(_ simulatorSet: URL, _ command: [String]) -> [String] {
    let arguments = ["--set", simulatorSet.path, "--simulators"] + command
    return assertCLIRunsSuccessfully(arguments)
  }
}
