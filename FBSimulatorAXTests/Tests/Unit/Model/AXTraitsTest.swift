/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AXRuntime
@testable import FBControlCore
@testable import FBSimulatorAX
import Foundation
import Testing

@Suite
struct AXTraitsTest {
  @Test
  func mappingNames() {
    let mapping = AXTraitToNameMap()
    #expect(mapping[AXTraits.link.rawValue] == "Link")
    #expect(mapping[AXTraits.button.rawValue] == "Button")
  }

  @Test
  func emptyTraitExtraction() {
    #expect(AXExtractTraits(0) == ["None"])
  }

  @Test
  func singleTraitExtraction() {
    #expect(AXExtractTraits(AXTraits.button.rawValue) == ["Button"])
  }

  @Test
  func unknownTraitExtraction() {
    #expect(AXExtractTraits(UInt64(1) << 63) == ["Unknown"])
  }

  @Test
  func combinedTraitExtraction() {
    #expect(AXExtractTraits(AXTraits.selected.rawValue | AXTraits.button.rawValue) == ["Button", "Selected"], "bit order")
  }

  @Test
  func combinedTraitExtractionWithUnknownTrait() {
    #expect(AXExtractTraits(AXTraits.button.rawValue | (UInt64(1) << 63)) == ["Button", "Unknown"], "unknown bits last")
  }
}
