/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Disabled during swift-format 6.3 rollout, feel free to remove:
// swift-format-ignore-file: OrderedImports

import AXRuntime
import XCTest

@testable import FBControlCore

final class AXTraitsTest: XCTestCase {
  func testMappingNames() {
    let mapping = AXTraitToNameMap()
    XCTAssertEqual(mapping[NSNumber(value: AXTraits.link.rawValue)], "Link")
    XCTAssertEqual(mapping[NSNumber(value: AXTraits.button.rawValue)], "Button")
  }

  func testEmptyTraitExtraction() {
    XCTAssertEqual(AXExtractTraits(0), Set(["None"]))
  }

  func testSingleTraitExtraction() {
    XCTAssertEqual(AXExtractTraits(AXTraits.button.rawValue), Set(["Button"]))
  }

  func testUnknownTraitExtraction() {
    XCTAssertEqual(AXExtractTraits(UInt64(1) << 63), Set(["Unknown"]))
  }

  func testCombinedTraitExtraction() {
    let expectedSet: Set<String> = Set(["Button", "Selected"])
    XCTAssertEqual(AXExtractTraits(AXTraits.button.rawValue | AXTraits.selected.rawValue), expectedSet)
  }

  func testCombinedTraitExtractionWithUnknownTrait() {
    let expectedSet: Set<String> = Set(["Button", "Unknown"])
    XCTAssertEqual(AXExtractTraits(AXTraits.button.rawValue | (UInt64(1) << 63)), expectedSet)
  }
}
