/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControlKit
import XCTest

public extension XCTestCase {
  func assertParses<A: Equatable>(_ parser: Parser<A>, _ tokens: [String], _ expected: A) {
    do {
      let (_, actual) = try parser.parse(tokens)
      XCTAssertEqual(expected, actual)
    } catch let err {
      XCTFail("Query '\(tokens.joined(separator: " "))' failed to parse \(err)")
    }
  }

  func assertParsesAll<A: Equatable>(_ parser: Parser<A>, _ tokenExpectedPairs: [([String], A)]) {
    for (tokens, expected) in tokenExpectedPairs {
      assertParses(parser, tokens, expected)
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
      assertParseFails(parser, tokens)
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

@objc class TestWriter: NSObject, Writer {
  let buffer: FBConsumableBuffer = FBDataBuffer.consumableBuffer()
  var output: [String] = []

  func consumeData(_ data: Data) {
    buffer.consumeData(data)
    while let line = self.buffer.consumeLineString() {
      output.append(line)
    }
  }

  func consumeEndOfFile() {}

  override var description: String {
    return output.joined(separator: "\n")
  }
}

extension FBiOSTargetQuery {
  public static func simulatorStates(_ states: [FBiOSTargetState]) -> FBiOSTargetQuery {
    return allTargets().simulatorStates(states)
  }

  public func simulatorStates(_ states: [FBiOSTargetState]) -> FBiOSTargetQuery {
    let indexSet = states.reduce(NSMutableIndexSet()) { indexSet, state in
      indexSet.add(Int(state.rawValue))
      return indexSet
    }
    return self.states(indexSet as IndexSet)
  }
}
