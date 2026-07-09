/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public extension FBTemporaryDirectory {

  /// Async wrapper for `withArchiveExtractedFromStream:compression:`.
  ///
  /// Extracts the archive from `input` into a temporary directory and returns
  /// its URL. The directory's teardown is registered with the current
  /// `FBTeardownContext`.
  func withArchiveExtractedAsync(fromStream input: FBProcessInput<AnyObject>, compression: FBCompressionFormat) async throws -> URL {
    let nsurl = try await bridgeFBFutureContext(self.withArchiveExtracted(fromStream: input, compression: compression))
    return nsurl as URL
  }

  /// Async wrapper for the `withArchiveExtractedFromStream:compression:` +
  /// `filesFromSubdirs:` pipeline.
  ///
  /// Extracts the archive from `input` into a temporary directory, then
  /// returns the unique file inside each immediate subdirectory of that
  /// directory. The directory's teardown is registered with the current
  /// `FBTeardownContext`.
  func filesFromSubdirsAsync(fromStream input: FBProcessInput<AnyObject>, compression: FBCompressionFormat) async throws -> [URL] {
    let context = self.withArchiveExtracted(fromStream: input, compression: compression)
    return try await bridgeFBFutureContextArray(self.files(fromSubdirs: context))
  }
}
