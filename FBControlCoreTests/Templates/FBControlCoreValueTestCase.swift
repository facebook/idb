/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

/// A Template for Tests that Provide Value-Like Objects.
class FBControlCoreValueTestCase: XCTestCase {

  /// Asserts that values are equal when copied.
  func assertEquality(ofCopy values: [NSObject]) {
    for value in values {
      let valueCopy = value.copy() as! NSObject
      let valueCopyCopy = valueCopy.copy() as! NSObject
      XCTAssertEqual(value, valueCopy)
      XCTAssertEqual(value, valueCopyCopy)
      XCTAssertEqual(valueCopy, valueCopyCopy)
    }
  }
}
