/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension OutputStream {

  /// Writes all of `bytes`, however many writes the stream takes to accept them.
  public func writeAll(_ bytes: UnsafeRawBufferPointer) throws {
    guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else {
      return
    }
    var offset = 0
    while offset < bytes.count {
      let written = write(base + offset, maxLength: bytes.count - offset)
      guard written > 0 else {
        throw streamError ?? CocoaError(.fileWriteUnknown)
      }
      offset += written
    }
  }

  public func writeAll(_ data: Data) throws {
    try data.withUnsafeBytes { try writeAll($0) }
  }
}
