/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import IDBGRPCSwift
import Testing

@Suite
struct StreamCapabilitiesTests {

  @Test
  func everyCompressionIsAdvertisedWhateverIsOnThePath() {
    var info = Idb_CompanionInfo()
    info.setStreamCapabilities()

    #expect(info.supportedCompressions == [.gzip, .zstd])
    #expect(info.zstdZipStreams)
  }
}
