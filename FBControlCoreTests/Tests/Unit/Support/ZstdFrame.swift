/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// zstd frames written without a compressor, as the tests cannot rely on one being installed.
enum ZstdFrame {

  /// `data` in a frame of uncompressed blocks, with a 128 KiB window, which is also the most a block can hold.
  static func stored(_ data: Data) -> Data {
    var frame = Data([0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x38])
    var offset = data.startIndex
    repeat {
      let size = min(data.endIndex - offset, 1 << 17)
      let last = offset + size == data.endIndex
      let header = UInt32(size) << 3 | (last ? 1 : 0)
      frame.append(contentsOf: [UInt8(header & 0xFF), UInt8(header >> 8 & 0xFF), UInt8(header >> 16)])
      frame.append(data[offset..<offset + size])
      offset += size
    } while offset < data.endIndex
    return frame
  }
}
