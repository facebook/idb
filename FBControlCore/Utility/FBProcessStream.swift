/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A Protocol that wraps the standard stream stdout, stderr, stdin.
@objc public protocol FBStandardStream: NSObjectProtocol {
  /// Attaches to the output, returning an FBProcessStreamAttachment.
  func attach() -> FBFuture<FBProcessStreamAttachment>

  /// Tears down the output.
  func detach() -> FBFuture<NSNull>
}

/// Provides information about the state of a stream.
@objc public protocol FBStandardStreamTransfer: NSObjectProtocol {
  /// The number of bytes transferred.
  var bytesTransferred: Int { get }

  /// An error, if any has occurred in the streaming of data to the input.
  var streamError: Error? { get }
}

/// Process Output that can be provided through a file.
@objc public protocol FBProcessFileOutput: NSObjectProtocol {
  /// The File Path to write to.
  var filePath: String { get }

  /// Should be called just after the file path has been written to.
  func startReading() -> FBFuture<NSNull>

  /// Should be called just after the file has stopped being written to.
  func stopReading() -> FBFuture<NSNull>
}

/// Process Output that can be provided through a file.
@objc(FBProcessOutput)
public protocol FBProcessOutputProtocol: NSObjectProtocol {
  /// Allows the receiver to be written to via a file instead of via a file handle.
  func providedThroughFile() -> FBFuture<FBProcessFileOutput>

  /// Allows the receiver to be written to via a Data Consumer.
  func providedThroughConsumer() -> FBFuture<FBDataConsumer>
}

// MARK: - Conformance extensions for ObjC classes

extension FBProcessOutput: FBStandardStream, FBProcessOutputProtocol {}
extension FBProcessInput: FBStandardStream {}
