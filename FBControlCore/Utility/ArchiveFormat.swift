/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// What an archive is, from its first bytes.
public enum ArchiveFormat: Equatable, Sendable {
  case zip
  /// A zip compressed with zstd, which starts with `zstdZipMarker`.
  case zstdZip
  /// A zstd frame or a skippable frame, other than `zstdZipMarker`.
  case zstd
  case gzip
  /// Anything else, which is read as a tar.
  case other
  /// Fewer than `detectableLength` bytes, which is too few to tell.
  case undetermined

  /// The bytes `detect` needs, other than to tell `zstdZip` from `zstd`, which takes all of `zstdZipMarker`.
  public static let detectableLength = 4

  /// The zstd skippable frame that `CompanionInfo.zstd_zip_streams` clients start a compressed zip with.
  public static let zstdZipMarker = Data([0x5E, 0x2A, 0x4D, 0x18, 0x08, 0x00, 0x00, 0x00]) + Data("idb-zip\0".utf8)

  /// The bytes to read before calling `detect` for it to tell every format apart.
  public static let sniffLength = zstdZipMarker.count

  public static func detect(_ head: Data) -> ArchiveFormat {
    guard head.count >= detectableLength else {
      return .undetermined
    }
    if head.starts(with: zstdZipMarker) {
      return .zstdZip
    }
    if head.starts(with: ZipSignature.localHeaderBytes) {
      return .zip
    }
    if head.starts(with: [0x1F, 0x8B]) {
      return .gzip
    }
    let magic = Array(head.prefix(4))
    let isFrame = magic == [0x28, 0xB5, 0x2F, 0xFD]
    let isSkippableFrame = magic[0] & 0xF0 == 0x50 && magic[1...] == [0x2A, 0x4D, 0x18]
    return isFrame || isSkippableFrame ? .zstd : .other
  }
}
