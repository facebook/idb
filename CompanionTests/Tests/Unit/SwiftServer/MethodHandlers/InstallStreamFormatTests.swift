/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import FBArtifactStaging
import FBControlCore
import Foundation
import IDBGRPCSwift
import Testing

@Suite
struct InstallStreamFormatTests {

  enum Head: String, CaseIterable, CustomTestStringConvertible {
    case zip
    case zstdFrame
    case zstdZipMarker
    case otherSkippableFrame
    case gzip
    case ustarTar
    case tooShort
    case empty

    var bytes: Data {
      switch self {
      case .zip:
        return Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00])
      case .zstdFrame:
        return Data([0x28, 0xB5, 0x2F, 0xFD, 0x04, 0x00])
      case .zstdZipMarker:
        return Data([0x5E, 0x2A, 0x4D, 0x18, 0x08, 0x00, 0x00, 0x00]) + Data("idb-zip\0".utf8) + Data([0x28, 0xB5, 0x2F, 0xFD])
      case .otherSkippableFrame:
        return Data([0x50, 0x2A, 0x4D, 0x18, 0x04, 0x00, 0x00, 0x00])
      case .gzip:
        return Data([0x1F, 0x8B, 0x08, 0x00])
      case .ustarTar:
        return Data("A.app/".utf8) + Data(count: 251) + Data("ustar\0".utf8)
      case .tooShort:
        return Data([0x1F, 0x8B])
      case .empty:
        return Data()
      }
    }

    var testDescription: String { rawValue }
  }

  /// The format a stream is read as, for each head and declared compression.
  static let formats: [(Head, FBCompressionFormat, InstallStreamFormat)] = [
    (.zip, .GZIP, .zip),
    (.zip, .ZSTD, .zip),
    (.zstdZipMarker, .GZIP, .zstdZip),
    (.zstdZipMarker, .ZSTD, .zstdZip),
    (.zstdFrame, .GZIP, .gzipTar),
    (.zstdFrame, .ZSTD, .zstdTar),
    (.otherSkippableFrame, .GZIP, .gzipTar),
    (.otherSkippableFrame, .ZSTD, .zstdTar),
    (.gzip, .GZIP, .gzipTar),
    (.gzip, .ZSTD, .gzipTar),
    (.ustarTar, .GZIP, .gzipTar),
    (.ustarTar, .ZSTD, .gzipTar),
    (.tooShort, .GZIP, .gzipTar),
    (.tooShort, .ZSTD, .zstdTar),
    (.empty, .GZIP, .gzipTar),
    (.empty, .ZSTD, .zstdTar),
  ]

  @Test(arguments: formats)
  func aStream(_ head: Head, _ declared: FBCompressionFormat, _ expected: InstallStreamFormat) {
    #expect(InstallMethodHandler.streamFormat(initial: head.bytes, declared: declared) == expected)
  }
}
