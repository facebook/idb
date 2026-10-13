/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

@Suite
struct ConcatedJsonParserTests {

  @Test
  func plainSmallJsonParse() throws {
    let json = """
      {"hello": "world"}
      """

    #expect(try parse(string: json) == ["hello": "world"])
  }

  @Test
  func plainDoubleJsonParse() throws {
    let json = """
      {"hello": "world"}
      {"second": "value"}
      """

    #expect(try parse(string: json) == ["hello": "world", "second": "value"])
  }

  @Test
  func withCurlyBracketsInString() throws {
    let json = """
      {"hello": "wor{ld"}
      {"second": "value"}
      """

    #expect(try parse(string: json) == ["hello": "wor{ld", "second": "value"])
  }

  @Test
  func withEscapedCharatersInString() throws {
    let json = """
      {"hello": "worl\\"d"}
      {"second": "value"}
      """

    #expect(try parse(string: json) == ["hello": "worl\"d", "second": "value"])
  }

  @Test
  func throwsIncorrectJson() throws {
    let json = """
      {"hello": 1"world"1}
      """
    #expect(throws: (any Error).self) { try parse(string: json) }
  }

  private func parse(string: String) throws -> [String: String] {
    guard let json = try ConcatedJsonParser.parseConcatenatedJSON(from: string) as? [String: String] else {
      throw NSError(domain: "Json parsed with incorrect type", code: 0)
    }

    return json
  }
}
