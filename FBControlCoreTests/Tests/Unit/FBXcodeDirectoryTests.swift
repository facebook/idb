/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Disabled during swift-format 6.3 rollout, feel free to remove:
// swift-format-ignore-file: OrderedImports

import XCTest

@testable import FBControlCore

final class FBXcodeDirectoryTests: XCTestCase {
  func testXcodeSelect() throws {
    let directory = try FBXcodeDirectory.xcodeSelectDeveloperDirectory().await(withTimeout: 10) as String
    assertDirectory(directory)
  }

  func testFromSymlink() throws {
    let directory = try FBXcodeDirectory.symlinkedDeveloperDirectory()
    assertDirectory(directory)
  }

  func assertDirectory(_ directory: String) {
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory)
    XCTAssertTrue(exists)
    XCTAssertTrue(isDirectory.boolValue)

    let expectedContents = NSSet(array: ["Applications", "Platforms"])
    let actualContents = try? FileManager.default.contentsOfDirectory(atPath: directory)
    let intersection = NSMutableSet(array: actualContents ?? [])
    intersection.intersect(expectedContents as! Set<AnyHashable>)

    XCTAssertEqual(intersection.copy() as! NSSet, expectedContents)
  }
}
