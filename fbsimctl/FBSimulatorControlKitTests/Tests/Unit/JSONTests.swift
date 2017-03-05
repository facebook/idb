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

class JSONTests : XCTestCase {

  func testEncodesContainerJSON() {
    let input: [String : AnyObject] = [
      "foo" : "bar" as AnyObject,
      "baz" : NSNull(),
    ]
    do {
      let json = try JSON.encode(input as AnyObject)
      XCTAssertEqual(try json.getValue("foo").getString(), "bar")
      let _ = json.decode()
      let _ = try json.decodeContainer()
    } catch let error {
      XCTFail("JSON Failure \(error)")
    }
  }

  func testEncodesContainerPlainString() {
    let input = "foo"
    do {
      let json = try JSON.encode(input as AnyObject)
      XCTAssertEqual(try json.getString(), "foo")
      let _ = json.decode()
      if case .some = try? json.decodeContainer() {
        XCTFail("\(input) should fail decodeContainer")
      }
    } catch let error {
      XCTFail("JSON Failure \(error)")
    }
  }

  func testParsesBoolFromNumber() {
    let input: [String : AnyObject] = [
      "value" : NSNumber(booleanLiteral: false)
    ]
    do {
      var json = try JSON.encode(input as AnyObject)
      XCTAssertEqual(try json.getValue("value").getBool(), false)
      json = JSON.dictionary(["value" : JSON.bool(false)])
      XCTAssertEqual(try json.getValue("value").getBool(), false)
      json = JSON.dictionary(["value" : JSON.number(NSNumber(booleanLiteral: true))])
      XCTAssertEqual(try json.getValue("value").getBool(), true)
    } catch let error {
      XCTFail("JSON Failure \(error)")
    }
  }

}
