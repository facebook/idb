/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import IDBGRPCSwift

extension FBCompressionFormat {
  /// A compression the companion does not recognize is read as gzip, which is also what a stream without a compression frame uses.
  init(_ compression: Idb_Payload.Compression) {
    switch compression {
    case .gzip, .UNRECOGNIZED:
      self = .GZIP
    case .zstd:
      self = .ZSTD
    }
  }
}

extension Idb_Payload.Compression {
  init(_ format: FBCompressionFormat) {
    switch format {
    case .GZIP:
      self = .gzip
    case .ZSTD:
      self = .zstd
    }
  }
}

/// What this companion can decompress from a stream. Resolved once, when the companion starts,
/// from the `PATH` its subprocesses inherit.
struct StreamCapabilities: Sendable {
  let compressions: [FBCompressionFormat]
  let zstdDecompressorPath: String?

  init(searchPath: String?) {
    compressions = FBArchiveOperations.streamCompressions(searchPath: searchPath)
    zstdDecompressorPath = FBArchiveOperations.zstdDecompressorPath(searchPath: searchPath)
  }
}

extension Idb_CompanionInfo {
  mutating func setStreamCapabilities(_ capabilities: StreamCapabilities) {
    supportedCompressions = capabilities.compressions.map(Idb_Payload.Compression.init)
    zstdZipStreams = capabilities.zstdDecompressorPath != nil
  }
}
