/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

@testable import FBSimulatorControlKit
import XCTest

public extension XCTestCase {
  func assertParses<A: Equatable>(_ parser: Parser<A>, _ tokens: [String], _ expected: A, file: StaticString = #file, line: UInt = #line) {
    do {
      let (_, actual) = try parser.parse(tokens)
      XCTAssertEqual(expected, actual, file: file, line: line)
    } catch let err {
      XCTFail("Query '\(tokens.joined(separator: " "))' failed to parse \(err)", file: file, line: line)
    }
  }

  func assertParsesAll<A: Equatable>(_ parser: Parser<A>, _ tokenExpectedPairs: [([String], A)], file: StaticString = #file, line: UInt = #line) {
    for (tokens, expected) in tokenExpectedPairs {
      assertParses(parser, tokens, expected, file: file, line: line)
    }
  }

  func assertParseFails<A>(_ parser: Parser<A>, _ tokens: [String], file: StaticString = #file, line: UInt = #line) {
    do {
      let (_, actual) = try parser.parse(tokens)
      XCTFail("Query '\(tokens.joined(separator: " "))' should have failed to parse but did \(actual)", file: file, line: line)
    } catch {
      // Passed
    }
  }

  func assertFailsToParseAll<A>(_ parser: Parser<A>, _ tokensList: [[String]], file: StaticString = #file, line: UInt = #line) {
    for tokens in tokensList {
      assertParseFails(parser, tokens, file: file, line: line)
    }
  }

  func assertCLIRunsSuccessfully(_ arguments: [String], file: StaticString = #file, line: UInt = #line) -> [String] {
    let writer = TestWriter()
    let cli = CLI.fromArguments(arguments, environment: [:])
    let reporter = cli.createReporter(writer)
    let runner = CLIRunner(cli: cli, writer: writer, reporter: reporter)
    let result = runner.runForStatus()
    XCTAssertEqual(result, 0, "Expected a succesful result, but got \(result), output \(writer)", file: file, line: line)
    return writer.output
  }

  func temporaryDirectory() -> URL {
    return URL.urlRelativeTo(NSTemporaryDirectory(), component: "FBSimulatorControlKitTests", isDirectory: true)
  }
}

@objc class TestWriter: NSObject, Writer {
  let buffer = FBLineBuffer.consumableBuffer()
  var output: [String] = []

  func consumeData(_ data: Data) {
    buffer.consumeData(data)
    while let line = self.buffer.consumeLineString() {
      output.append(line)
    }
  }

  func consumeEndOfFile() {
  }

  override var description: String {
    return output.joined(separator: "\n")
  }
}

extension FBiOSTargetQuery {
  public static func simulatorStates(_ states: [FBSimulatorState]) -> FBiOSTargetQuery {
    return allTargets().simulatorStates(states)
  }

  public func simulatorStates(_ states: [FBSimulatorState]) -> FBiOSTargetQuery {
    let indexSet = states.reduce(NSMutableIndexSet()) { indexSet, state in
      indexSet.add(Int(state.rawValue))
      return indexSet
    }
    return self.states(indexSet as IndexSet)
  }
}
