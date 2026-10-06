/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation

/// Reads `data` at most `pieceSize` bytes at a time, as an archive arrives over a pipe.
final class DataSource: ByteSource {

  private let data: Data
  private let pieceSize: Int
  private var offset = 0

  init(_ data: Data, pieceSize: Int = .max) {
    self.data = data
    self.pieceSize = pieceSize
  }

  func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
    let count = min(buffer.count, data.count - offset, pieceSize)
    data.copyBytes(to: buffer.bindMemory(to: UInt8.self), from: offset..<offset + count)
    offset += count
    return count
  }
}

extension ByteSource {

  /// Everything left to read.
  func readAll() throws -> Data {
    var contents = Data()
    var chunk = [UInt8](repeating: 0, count: 1 << 16)
    while case let count = try chunk.withUnsafeMutableBytes({ try read(into: $0) }), count > 0 {
      contents.append(contentsOf: chunk[..<count])
    }
    return contents
  }
}
