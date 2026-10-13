/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AXRuntime
@testable import FBControlCore
@testable import FBSimulatorAX
import XCTest

final class AXTraitsTest: XCTestCase {
  func testMappingNames() {
    let mapping = AXTraitToNameMap()
    XCTAssertEqual(mapping[AXTraits.link.rawValue], "Link")
    XCTAssertEqual(mapping[AXTraits.button.rawValue], "Button")
  }

  func testEmptyTraitExtraction() {
    XCTAssertEqual(AXExtractTraits(0), ["None"])
  }

  func testSingleTraitExtraction() {
    XCTAssertEqual(AXExtractTraits(AXTraits.button.rawValue), ["Button"])
  }

  func testUnknownTraitExtraction() {
    XCTAssertEqual(AXExtractTraits(UInt64(1) << 63), ["Unknown"])
  }

  func testCombinedTraitExtraction() {
    XCTAssertEqual(AXExtractTraits(AXTraits.selected.rawValue | AXTraits.button.rawValue), ["Button", "Selected"], "bit order")
  }

  func testCombinedTraitExtractionWithUnknownTrait() {
    XCTAssertEqual(AXExtractTraits(AXTraits.button.rawValue | (UInt64(1) << 63)), ["Button", "Unknown"], "unknown bits last")
  }
}
