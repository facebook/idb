/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBDeviceControl
import XCTest

final class FBSpringboardIconLayoutTests: XCTestCase {

  func testParsesRawIconLayoutPages() throws {
    let rawLayout: [[[String: Any]]] = [
      [
        [
          "bundleIdentifier": "com.example.dock",
          "displayIdentifier": "com.example.dock",
          "displayName": "Dock App",
        ]
      ],
      [
        [
          "bundleIdentifier": "com.example.app",
          "displayIdentifier": "com.example.app",
          "displayName": "Example",
        ],
        [
          "listType": "folder",
          "displayName": "Folder",
          "iconLists": [
            [
              [
                "bundleIdentifier": "com.example.foldered",
                "displayIdentifier": "com.example.foldered",
                "displayName": "Foldered",
              ]
            ]
          ],
        ],
      ],
    ]

    let layout = try FBSpringboardIconLayout(rawValue: rawLayout)

    XCTAssertEqual(layout.pageCount, 2)
    XCTAssertEqual(layout.totalEntries, 3)
    XCTAssertEqual(layout.flattenedBundleIdentifierPages(), [["com.example.dock"], ["com.example.app"]])
    XCTAssertEqual(layout.iconsByBundleID["com.example.app"]?["displayName"] as? String, "Example")
    XCTAssertEqual(layout.rawValue.count, rawLayout.count)
  }

  func testRejectsUnexpectedRawIconLayoutShape() {
    XCTAssertThrowsError(try FBSpringboardIconLayout(rawValue: ["not": "pages"])) { error in
      guard case FBSpringboardServicesError.unexpectedResponse(let command, let expected, let actual) = error else {
        XCTFail("Expected unexpectedResponse error, got \(error)")
        return
      }

      XCTAssertEqual(command, "getIconState")
      XCTAssertEqual(expected, "an array of icon pages")
      XCTAssertTrue(actual.contains("not"))
    }
  }

  func testValidationErrorReportsFirstMismatchedPage() {
    let expected = FBSpringboardIconLayout(
      pages: [
        [["displayIdentifier": "com.example.dock"]],
        [["displayIdentifier": "com.example.one"]],
      ])
    let actual = FBSpringboardIconLayout(
      pages: [
        [["displayIdentifier": "com.example.dock"]],
        [["displayIdentifier": "com.example.two"]],
      ])

    XCTAssertEqual(
      expected.validationError(comparedTo: actual),
      "page 1 identifiers differ at position 0: sent 'com.example.one', got 'com.example.two'")
  }
}
