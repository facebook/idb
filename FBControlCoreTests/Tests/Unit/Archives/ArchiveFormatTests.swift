/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

@Suite
struct ArchiveFormatTests {

  static let heads: [(Data, ArchiveFormat)] = [
    (Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00]), .zip),
    (ArchiveFormat.zstdZipMarker + Data([0x28, 0xB5, 0x2F, 0xFD]), .zstdZip),
    (ArchiveFormat.zstdZipMarker.prefix(8), .zstd),
    (Data([0x28, 0xB5, 0x2F, 0xFD, 0x04, 0x00]), .zstd),
    (Data([0x50, 0x2A, 0x4D, 0x18, 0x04, 0x00, 0x00, 0x00]), .zstd),
    (Data([0x5F, 0x2A, 0x4D, 0x18, 0x04, 0x00, 0x00, 0x00]), .zstd),
    (ArchiveFormat.zstdZipMarker.prefix(8) + Data("idb-tar\0".utf8), .zstd),
    (Data([0x1F, 0x8B, 0x08, 0x00]), .gzip),
    (Data("A.app/".utf8) + Data(count: 251) + Data("ustar\0".utf8), .other),
    (Data([0x50, 0x4B, 0x05, 0x06]), .other),
    (Data([0x1F, 0x8B]), .undetermined),
    (Data(), .undetermined),
  ]

  @Test(arguments: heads)
  func detectsFromTheHead(head: Data, format: ArchiveFormat) {
    #expect(ArchiveFormat.detect(head) == format)
  }

  @Test
  func detectsFromASlice() {
    let bytes = Data([0x00, 0x1F, 0x8B, 0x08, 0x00])
    #expect(ArchiveFormat.detect(bytes.dropFirst()) == .gzip)
  }
}
