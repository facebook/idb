/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import FBControlCore

final class FBBinaryDescriptorTests: XCTestCase {
  func testFatBinary() throws {
    // xctest is a fat binary.
    let descriptor = try FBBinaryDescriptor.binary(withPath: ProcessInfo.processInfo.arguments.first!)
    XCTAssertNotNil(descriptor)
    XCTAssertNotNil(descriptor.uuid)

    let rpaths = try descriptor.rpaths()
    XCTAssertNotNil(rpaths)
  }

  func test64BitMacosCommand() throws {
    // codesign is not a fat binary.
    let descriptor = try FBBinaryDescriptor.binary(withPath: "/usr/bin/codesign")
    XCTAssertNotNil(descriptor)
    XCTAssertNotNil(descriptor.uuid)
  }
}
