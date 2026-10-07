/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The File Reader States
@objc public enum FBFileReaderState: UInt {
  case notStarted = 0
  case reading = 1
  case finishedReadingNormally = 2
  case finishedReadingInError = 3
  // `ECANCELED`, which a raw value cannot reference. The state crosses futures as its raw value.
  case finishedReadingByCancellation = 89
}

/// A Protocol for defining file reading.
@objc public protocol FileReaderProtocol {
  /// Starts reading the file.
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
