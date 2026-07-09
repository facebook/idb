/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import XCTest

extension XCTestCase {

  class func iosUnitTestBundleFixture() -> Bundle {
    let fixturePath = Bundle(for: self).path(forResource: "iOSUnitTestFixture", ofType: "xctest")!
    return Bundle(path: fixturePath)!
  }

  class func macUnitTestBundleFixture() -> Bundle {
    let fixturePath = Bundle(for: self).path(forResource: "MacUnitTestFixture", ofType: "xctest")!
    return Bundle(path: fixturePath)!
  }

  class func macCommonApplication() throws -> FBBundleDescriptor {
    let path = Bundle(for: self).path(forResource: "MacCommonApp", ofType: "app")!
    return try FBBundleDescriptor.bundle(fromPath: path)
  }
}
