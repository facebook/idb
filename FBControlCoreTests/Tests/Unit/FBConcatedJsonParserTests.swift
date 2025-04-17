/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import FBControlCore

class FBConcatedJsonParserTests: XCTestCase {

  func testPlainSmallJsonParse() throws {
    let json = """
      {"hello": "world"}
      """

    try XCTAssertEqual(parse(string: json), ["hello": "world"])
  }

  func testPlainDoubleJsonParse() throws {
    let json = """
      {"hello": "world"}
      {"second": "value"}
      """

    try XCTAssertEqual(parse(string: json), ["hello": "world", "second": "value"])
  }

  func testWithCurlyBracketsInString() throws {
    let json = """
      {"hello": "wor{ld"}
      {"second": "value"}
      """

    try XCTAssertEqual(parse(string: json), ["hello": "wor{ld", "second": "value"])
  }

  func testWithEscapedCharatersInString() throws {
    let json = """
      {"hello": "worl\\"d"}
      {"second": "value"}
      """

    try XCTAssertEqual(parse(string: json), ["hello": "worl\"d", "second": "value"])
  }

  func testThrowsIncorrectJson() throws {
    let json = """
      {"hello": 1"world"1}
      """
    XCTAssertThrowsError(try parse(string: json))
  }

  private func parse(string: String) throws -> [String: String] {
    guard let json = try FBConcatedJsonParser.parseConcatenatedJSON(from: string) as? [String: String] else {
      throw NSError(domain: "Json parsed with incorrect type", code: 0)
    }

    return json
  }
}
