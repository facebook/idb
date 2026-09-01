/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBDeviceControl
import Testing

@Suite
struct FBSpringboardIconLayoutTests {

  @Test
  func parsesRawIconLayoutPages() throws {
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

    #expect((layout.pageCount) == (2))
    #expect((layout.totalEntries) == (3))
    #expect((layout.flattenedBundleIdentifierPages()) == ([["com.example.dock"], ["com.example.app"]]))
    #expect((layout.iconsByBundleID["com.example.app"]?["displayName"] as? String) == ("Example"))
    #expect((layout.rawValue.count) == (rawLayout.count))
  }

  @Test
  func rejectsUnexpectedRawIconLayoutShape() {
    do {
      _ = try FBSpringboardIconLayout(rawValue: ["not": "pages"])
      Issue.record("Expected unexpectedResponse error to be thrown")
    } catch FBSpringboardServicesError.unexpectedResponse(let command, let expected, let actual) {
      #expect(command == "getIconState")
      #expect(expected == "an array of icon pages")
      #expect(actual.contains("not"))
    } catch {
      Issue.record("Expected unexpectedResponse error, got \(error)")
    }
  }

  @Test
  func validationErrorReportsFirstMismatchedPage() {
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

    #expect((expected.validationError(comparedTo: actual)) == ("page 1 identifiers differ at position 0: sent 'com.example.one', got 'com.example.two'"))
  }
}
