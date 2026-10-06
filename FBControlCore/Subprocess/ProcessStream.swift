/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A Protocol that wraps the standard stream stdout, stderr, stdin.
@objc public protocol StandardStream: NSObjectProtocol {
  /// Attaches to the output, returning an FBProcessStreamAttachment.
  func attach() -> FBFuture<FBProcessStreamAttachment>

  /// Tears down the output.
  func detach() -> FBFuture<NSNull>
}

/// Provides information about the state of a stream.
@objc public protocol StandardStreamTransfer: NSObjectProtocol {
  /// The number of bytes transferred.
  var bytesTransferred: Int { get }

  /// An error, if any has occurred in the streaming of data to the input.
  var streamError: Error? { get }
}

// MARK: - Conformance extensions for ObjC classes

extension FBProcessInput: StandardStream {}
