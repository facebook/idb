/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Returns a long-lived operation that can be awaited for completion or cancelled.
public protocol LogOperation: AnyObject {

  /// The data consumer attached to the underlying log stream.
  var consumer: any FBDataConsumer { get }

  /// Awaits completion of the log operation. Cancelling the calling task signals
  /// the operation to terminate.
  func waitUntilCompleted() async throws
}

public protocol LogCommands: AnyObject {

  func tailLog(arguments: [String], consumer: any FBDataConsumer) async throws -> any LogOperation
}
