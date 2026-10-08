/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

/// The frames are written by `zstd --no-check`, as hex, so the tests do not need a zstd on the host.
@Suite
struct ZstdSourceTests {

  private static let first = frame("28b52ffd0058310000666972737420")
  private static let second = frame("28b52ffd00583100007365636f6e64")
  /// A million `x`s, which decompress to many times the reader's buffer.
  private static let million = frame("28b52ffd00585400001078780100fbff39c00202001078020010780200107802001078020010780200107803120a78")

  private static func frame(_ hex: String) -> Data {
    var bytes = Data()
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      bytes.append(UInt8(hex[index..<next], radix: 16)!)
      index = next
    }
    return bytes
  }

  @Test
  func framesAreReadOneAfterAnother() throws {
    let contents = Self.first + Self.second

    #expect(try ZstdSource(DataSource(contents, pieceSize: 7)).readAll() == Data("first second".utf8))
  }

  @Test
  func skippableFramesAreSkipped() throws {
    let contents = ArchiveFormat.zstdZipMarker + Self.first

    #expect(try ZstdSource(DataSource(contents)).readAll() == Data("first ".utf8))
  }

  @Test
  func outputHeldAfterTheInputEndsIsStillRead() throws {
    #expect(try ZstdSource(DataSource(Self.million)).readAll() == Data(repeating: UInt8(ascii: "x"), count: 1_000_000))
  }

  @Test
  func aTruncatedZstdIsCorrupt() throws {
    #expect(throws: ArchiveError.corrupt("the zstd ends early")) {
      try ZstdSource(DataSource(Self.million.prefix(Self.million.count / 2))).readAll()
    }
  }

  @Test
  func anythingAfterAFrameIsCorrupt() throws {
    let contents = Self.first + Data("trailing".utf8)

    #expect(throws: ArchiveError.corrupt("the zstd does not decompress")) {
      try ZstdSource(DataSource(contents)).readAll()
    }
  }

  @Test
  func onlyAZstdIsDecompressed() throws {
    let plain = Data("not compressed".utf8)

    #expect(try ZstdSource.ifZstd(DataSource(plain)).readAll() == plain)
    #expect(try ZstdSource.ifZstd(DataSource(Data())).readAll().isEmpty)
    #expect(try ZstdSource.ifZstd(DataSource(Self.first)).readAll() == Data("first ".utf8))
    #expect(try ZstdSource.ifZstd(DataSource(ArchiveFormat.zstdZipMarker + Self.second)).readAll() == Data("second".utf8))
  }

  @Test
  func drainingAZstdDoesNotDecompressIt() throws {
    var corrupt = Self.million
    corrupt[corrupt.count / 2] ^= 0xFF
    let raw = DataSource(corrupt, pieceSize: 10)

    try ZstdSource(raw).drain()

    #expect(try raw.readAll().isEmpty)
  }
}
