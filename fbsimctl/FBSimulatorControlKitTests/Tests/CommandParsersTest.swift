// Copyright 2004-present Facebook. All Rights Reserved.

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

class QueryParserTests : XCTestCase {
  func testParsesSimpleQueries() {
    let queries = [
      ["iPhone 5"],
      ["iPad 2"],
      ["creating"],
      ["shutdown"],
      ["booted"],
      ["booting"],
      ["shutting-down"],
      ["B8EEA6C4-841B-47E5-92DE-014E0ECD8139"]
    ]
    for query in queries {
      self.assertParses(query)
    }
  }

  func testFailsSimpleQueries() {
    let queries = [
      ["Galaxy S5"],
      ["Nexus Chromebook Pixel G4 Droid S5 S1 S4 4S"],
      ["makingtea"],
      ["B8EEA6C4-47E5-92DE-014E0ECD8139"],
      []
    ]
    for query in queries {
      self.assertParseFails(query)
    }
  }

  func testParsesCompoundQueries() {
    let queries = [
      ["iPhone 5", "iPad 2"],
      ["creating", "booting", "shutdown"],
      ["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8", "D7DA55E9-26FF-44FD-91A1-5B30DB68A4BB"],
      ["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "124DAC9C-4DFF-4F0C-9828-998CCFFCD4C8", "booted"]
    ]
    for query in queries {
      self.assertParses(query)
    }
  }

  func testParsesPartially() {
    let queries = [
      ["iPhone 5", "Nexus 5", "iPad 2"],
      ["creating", "booting", "jelly", "shutdown"],
      ["B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "banana", "D7DA55E9-26FF-44FD-91A1-5B30DB68A4BB"],
    ]
    for query in queries {
      self.assertParses(query)
    }
  }

  func testFailsPartialParse() {
    let queries = [
      ["Nexus 5", "iPhone 5", "iPad 2"],
      ["jelly", "creating", "booting", "shutdown"],
      ["banana", "B8EEA6C4-841B-47E5-92DE-014E0ECD8139", "D7DA55E9-26FF-44FD-91A1-5B30DB68A4BB"],
    ]
    for query in queries {
      self.assertParseFails(query)
    }
  }
}
