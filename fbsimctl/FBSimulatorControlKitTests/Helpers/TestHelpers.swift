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

public extension XCTestCase {
  func assertParses(tokens: [String]) {
    do {
      let _ = try Query.parser().parse(tokens)
    } catch let err {
      XCTFail("Query '\(tokens.joinWithSeparator(" "))' failed to parse \(err)")
    }
  }

  func assertParseFails(tokens: [String]) {
    do {
      let (_, query) = try Query.parser().parse(tokens)
      XCTFail("Query '\(tokens.joinWithSeparator(" "))' should have failed to parse but did \(query)")
    } catch {
      // Passed
    }
  }
}