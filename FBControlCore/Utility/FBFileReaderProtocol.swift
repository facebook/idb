/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A Protocol for defining file reading.
@objc public protocol FBFileReaderProtocol {
  /// Starts the reading the file.
  @discardableResult
  func startReading() -> FBFuture<NSNull>

  /// Stops reading the file.
  @discardableResult
  func stopReading() -> FBFuture<NSNumber>

  /// Waits for the reader to finish reading, backing off to stopping in the event of a timeout.
  @discardableResult
  func finishedReading(withTimeout timeout: TimeInterval) -> FBFuture<NSNumber>

  /// The current state of the file reader.
  var state: FBFileReaderState { get }

  /// A Future that resolves when the reading of the file handle has no pending operations on the file descriptor.
  var finishedReading: FBFuture<NSNumber> { get }
}
