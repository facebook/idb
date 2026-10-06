/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
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

  /// The format an app stream is read as, for each head and declared compression.
  static let appFormats: [(Head, FBCompressionFormat, InstallStreamFormat)] = [
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

  @Test(arguments: appFormats)
  func anAppStream(_ head: Head, _ declared: FBCompressionFormat, _ expected: InstallStreamFormat) {
    #expect(InstallMethodHandler.streamFormat(initial: head.bytes, declared: declared, destination: .app) == expected)
  }

  /// Heads a stream declared zstd keeps that declaration for: a zstd frame, any skippable frame, or too little to tell.
  static let keepsZstd: Set<Head> = [.zstdFrame, .zstdZipMarker, .otherSkippableFrame, .tooShort, .empty]

  /// Every other kind is read as a tar whatever it starts with, a zip included, as only an app is read as a zip.
  @Test(arguments: [Idb_InstallRequest.Destination.xctest, .dsym, .dylib, .framework], Head.allCases)
  func anotherKindOfStream(_ destination: Idb_InstallRequest.Destination, _ head: Head) {
    #expect(InstallMethodHandler.streamFormat(initial: head.bytes, declared: .GZIP, destination: destination) == .gzipTar)
    #expect(InstallMethodHandler.streamFormat(initial: head.bytes, declared: .ZSTD, destination: destination) == (Self.keepsZstd.contains(head) ? .zstdTar : .gzipTar))
  }
}
