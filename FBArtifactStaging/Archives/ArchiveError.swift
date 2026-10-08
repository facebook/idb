/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Why an extractor stopped. Failures of the file system it writes to are thrown as `POSIXError`.
public enum ArchiveError: Error, Equatable {
  /// An archive this extractor does not read, though another extractor may.
  case unsupported(String)
  /// An archive that is damaged or truncated, which no extractor should read differently.
  case corrupt(String)
  /// An entry that would be written outside the extraction root, or through a symlink.
  case unsafePath(String)
  /// The tool extracting a stream exited unsuccessfully, with the tail of its standard error.
  case extractorFailed(exitCode: Int32, standardError: String)
}

extension ArchiveError: LocalizedError {

  public var errorDescription: String? {
    switch self {
    case .unsupported(let reason):
      return "Unsupported archive: \(reason)"
    case .corrupt(let reason):
      return "Corrupt archive: \(reason)"
    case .unsafePath(let path):
      return "Unsafe path in archive: \(path)"
    case .extractorFailed(let exitCode, let standardError):
      let description = "Exit Code \(exitCode) is not acceptable [0]"
      return standardError.isEmpty ? description : "\(description): \(standardError)"
    }
  }
}
