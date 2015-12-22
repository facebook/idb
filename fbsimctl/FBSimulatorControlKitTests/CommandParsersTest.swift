/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import XCTest
@testable import FBSimulatorControlKit

class SubcommandParsersTest : XCTestCase {

  func testParsesQueries() {
    let commands = [
      ["iPhone 5"],
      ["iPad 2"],
      ["creating"],
      ["shutdown"],
      ["booted"],
      ["booting"],
      ["shutting-down"],
      ["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]
    ]
    for command in commands {
      do {
        let _ = try Query.parser().parse(command)
      } catch let err {
        XCTFail("Command '\(command.joinWithSeparator(" "))' failed to parse \(err)")
      }
    }
  }

}
