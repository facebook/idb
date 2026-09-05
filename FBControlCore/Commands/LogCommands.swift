/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A long-lived operation that can be awaited for completion or cancelled.
public protocol LogOperation: AnyObject {

  /// The data consumer attached to the underlying log stream.
  var consumer: any FBDataConsumer { get }

  /// Cancelling the calling task terminates the operation.
  func waitUntilCompleted() async throws
}

public protocol LogCommands: AnyObject {

  func tailLog(arguments: [String], consumer: any FBDataConsumer) async throws -> any LogOperation
}
