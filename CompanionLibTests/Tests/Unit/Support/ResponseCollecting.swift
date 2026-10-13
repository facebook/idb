/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPCCore

final class CollectingWriter<Element: Sendable>: RPCWriterProtocol, @unchecked Sendable {
  private let lock = NSLock()
  private var written: [Element] = []

  var elements: [Element] { lock.withLock { written } }

  func write(_ element: Element) async throws {
    lock.withLock { written.append(element) }
  }

  func write(contentsOf elements: some Sequence<Element>) async throws {
    for element in elements {
      try await write(element)
    }
  }
}

/// Counts gzip member headers (magic, deflate, Unix OS byte). A client's `tar` stops at the end of the first member,
/// so anything after it is unread.
func gzipMembers(in data: Data) -> Int {
  let bytes = [UInt8](data)
  guard bytes.count >= 10 else { return 0 }
  return (0...(bytes.count - 10)).filter { offset in
    bytes[offset] == 0x1F && bytes[offset + 1] == 0x8B && bytes[offset + 2] == 0x08 && bytes[offset + 9] == 0x03
  }.count
}
