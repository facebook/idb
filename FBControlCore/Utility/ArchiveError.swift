/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Why an in-process extractor stopped. Failures of the file system it writes to are thrown as `POSIXError`.
public enum ArchiveError: Error, Equatable {
  /// An archive this extractor does not read, though another extractor may.
  case unsupported(String)
  /// An archive that is damaged or truncated, which no extractor should read differently.
  case corrupt(String)
  /// An entry that would be written outside the extraction root, or through a symlink.
  case unsafePath(String)
}
