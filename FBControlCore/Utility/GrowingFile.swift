/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A file that another writer is still appending to.
public enum GrowingFile {

  /// Copies the file at `path` to `output` as it grows, returning once
  /// `isComplete` holds and everything written by then has been copied.
  public static func copy(from path: String, to output: OutputStream, isComplete: () -> Bool) async throws {
    let file = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    defer { try? file.close() }
    while true {
      // Asked before reading, so that a write just before completion is not missed.
      let complete = isComplete()
      let data = try file.read(upToCount: 1 << 20) ?? Data()
      if !data.isEmpty {
        try output.writeAll(data)
        continue
      }
      if complete {
        return
      }
      try await Task.sleep(nanoseconds: 5_000_000)
    }
  }
}
