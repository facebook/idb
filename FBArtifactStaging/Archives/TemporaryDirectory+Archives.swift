/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

extension TemporaryDirectory {

  /// Extracts the archive in `pipe` into a temporary directory scoped to `body`.
  public func withArchiveExtracted<T>(
    fromStream pipe: BytePipe,
    compression: FBCompressionFormat,
    overrideModificationTime overrideMTime: Bool = false,
    _ body: (URL) async throws -> T
  ) async throws -> T {
    try await withTemporaryDirectory { tempDir in
      try await pipe.reading {
        try await ArchiveExtractors.stream(compression).extract(
          from: $0, to: tempDir.path,
          options: ArchiveExtractOptions(overrideModificationTime: overrideMTime),
          logger: logger)
      }
      return try await body(tempDir)
    }
  }

  /// Extracts the gzipped tar in `tarData` into a temporary directory scoped to `body`.
  public func withArchiveExtracted<T>(_ tarData: Data, _ body: (URL) async throws -> T) async throws -> T {
    try await withArchiveExtracted(fromStream: BytePipe(tarData), compression: .GZIP, body)
  }

  /// Extracts the archive at `filePath` into a temporary directory scoped to `body`.
  public func withArchiveExtracted<T>(
    fromFile filePath: String,
    overrideModificationTime overrideMTime: Bool,
    _ body: (URL) async throws -> T
  ) async throws -> T {
    try await withTemporaryDirectory { tempDir in
      try await ArchiveExtractors.default.extract(
        fromFile: filePath, to: tempDir.path,
        options: ArchiveExtractOptions(overrideModificationTime: overrideMTime),
        logger: logger)
      return try await body(tempDir)
    }
  }
}
