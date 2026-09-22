/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A failure to construct the companion's logger.
public enum IDBLoggerError: Error, CustomStringConvertible {

  /// The directory containing the requested log file did not exist and could not be created.
  case logDirectoryCreationFailed(path: String, underlyingError: any Error)

  /// The requested log file could not be opened for appending.
  case logFileOpenFailed(path: String, code: Int32)

  public var description: String {
    switch self {
    case let .logDirectoryCreationFailed(path, underlyingError):
      return "Couldn't create the log directory at \(path): \(underlyingError)"
    case let .logFileOpenFailed(path, code):
      return "Couldn't open the log file at \(path): \(String(cString: strerror(code)))"
    }
  }
}

// MARK: - LocalizedError

// So that a caller reporting through `localizedDescription` — as the companion's top-level
// error handling does — gets the description above rather than the bare case name.
extension IDBLoggerError: LocalizedError {
  public var errorDescription: String? {
    description
  }
}
