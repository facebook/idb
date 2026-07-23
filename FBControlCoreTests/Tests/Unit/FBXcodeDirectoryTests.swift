/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBXcodeDirectoryTests: XCTestCase {
  func testXcodeSelect() throws {
    let directory = try FBXcodeDirectory.xcodeSelectDeveloperDirectory()
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

    // `Platforms` is the stable marker of a Developer directory across Xcode versions.
    // Xcode 27 moved `Applications` out of Contents/Developer (to Contents/Applications,
    // where the renamed DeviceHub.app now lives), so it is no longer a reliable marker.
    let expectedContents = NSSet(array: ["Platforms"])
    let actualContents = try? FileManager.default.contentsOfDirectory(atPath: directory)
    let intersection = NSMutableSet(array: actualContents ?? [])
    intersection.intersect(expectedContents as! Set<AnyHashable>)

    XCTAssertEqual(intersection.copy() as! NSSet, expectedContents)
  }
}
