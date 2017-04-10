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
  func assertParses<A : Equatable>(_ parser: Parser<A>, _ tokens: [String], _ expected: A) {
    do {
      let (_, actual) = try parser.parse(tokens)
      XCTAssertEqual(expected, actual)
    } catch let err {
      XCTFail("Query '\(tokens.joined(separator: " "))' failed to parse \(err)")
    }
  }

  func assertParsesAll<A : Equatable>(_ parser: Parser<A>, _ tokenExpectedPairs: [([String], A)]) {
    for (tokens, expected) in tokenExpectedPairs {
      self.assertParses(parser, tokens, expected)
    }
  }

  func assertParseFails<A>(_ parser: Parser<A>, _ tokens: [String]) {
    do {
      let (_, actual) = try parser.parse(tokens)
      XCTFail("Query '\(tokens.joined(separator: " "))' should have failed to parse but did \(actual)")
    } catch {
      // Passed
    }
  }

  func assertFailsToParseAll<A>(_ parser: Parser<A>, _ tokensList: [[String]]) {
    for tokens in tokensList {
      self.assertParseFails(parser, tokens)
    }
  }

  func assertCLIRunsSuccessfully(_ arguments: [String]) -> [String] {
    let writer = TestWriter()
    let cli = CLI.fromArguments(arguments, environment: [:])
    let reporter = cli.createReporter(writer)
    let runner = CLIRunner(cli: cli, writer: writer, reporter: reporter)
    let result = runner.runForStatus()
    XCTAssertEqual(result, 0, "Expected a succesful result, but got \(result), output \(writer)")
    return writer.output
  }

  func temporaryDirectory() -> URL {
    return URL.urlRelativeTo(NSTemporaryDirectory(), component: "FBSimulatorControlKitTests", isDirectory: true)
  }
}

class TestWriter : Writer, CustomStringConvertible {
  var output: [String] = []

  func write(_ string: String) {
    output.append(string)
  }

  var description: String { get {
    return output.joined(separator: "\n")
  }}
}

extension FBiOSTargetQuery {
  public static func simulatorStates(_ states: [FBSimulatorState]) -> FBiOSTargetQuery {
    return self.allTargets().simulatorStates(states)
  }

  public func simulatorStates(_ states: [FBSimulatorState]) -> FBiOSTargetQuery {
    let indexSet = states.reduce(NSMutableIndexSet()) { (indexSet, state) in
      indexSet.add(Int(state.rawValue))
      return indexSet
    }
    return self.states(indexSet as IndexSet)
  }
}
