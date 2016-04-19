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
  func assertParses<A : Equatable>(parser: Parser<A>, _ tokens: [String], _ expected: A) {
    do {
      let (_, actual) = try parser.parse(tokens)
      XCTAssertEqual(expected, actual)
    } catch let err {
      XCTFail("Query '\(tokens.joinWithSeparator(" "))' failed to parse \(err)")
    }
  }

  func assertParsesAll<A : Equatable>(parser: Parser<A>, _ tokenExpectedPairs: [([String], A)]) {
    for (tokens, expected) in tokenExpectedPairs {
      self.assertParses(parser, tokens, expected)
    }
  }

  func assertParseFails<A>(parser: Parser<A>, _ tokens: [String]) {
    do {
      let (_, actual) = try parser.parse(tokens)
      XCTFail("Query '\(tokens.joinWithSeparator(" "))' should have failed to parse but did \(actual)")
    } catch {
      // Passed
    }
  }

  func assertFailsToParseAll<A>(parser: Parser<A>, _ tokensList: [[String]]) {
    for tokens in tokensList {
      self.assertParseFails(parser, tokens)
    }
  }

  func assertCLIRunsSuccessfully(arguments: [String]) -> [String] {
    let writer = TestWriter()
    let runner = CLIRunner(arguments: arguments, environment: [:], writer: writer)
    let result = runner.run()
    XCTAssertEqual(result, 0, "Expected a succesful result, but got \(result), output \(writer)")
    return writer.output
  }

  func temporaryDirectory() -> NSURL {
    return NSURL(fileURLWithPath: NSTemporaryDirectory()).URLByAppendingPathComponent("FBSimulatorControlKitTests")
  }
}

class TestWriter : Writer, CustomStringConvertible {
  var output: [String] = []

  func write(string: String) {
    output.append(string)
  }

  var description: String { get {
    return output.joinWithSeparator("\n")
  }}
}
