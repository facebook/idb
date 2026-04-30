/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// MARK: - FBiOSTargetOperation Protocol

/// A protocol that represents an operation of indeterminate length.
@objc public protocol FBiOSTargetOperation: NSObjectProtocol {

  /// A Future that resolves when the operation has completed.
  var completed: FBFuture<NSNull> { get }
}

public extension FBiOSTargetOperation {
  /// Cancels the operation and waits for the cancellation to complete.
  func cancelAsync() async throws {
    try await bridgeFBFutureVoid(self.completed.cancel())
  }

  /// Waits for the operation to complete.
  func awaitCompletionAsync() async throws {
    try await bridgeFBFutureVoid(self.completed)
  }
}

// MARK: - FBiOSTargetOperationWrapper

private class FBiOSTargetOperationWrapper: NSObject, FBiOSTargetOperation {

  let completed: FBFuture<NSNull>

  init(completed: FBFuture<NSNull>) {
    self.completed = completed
    super.init()
  }
}

/// C function replacement: called from the @_cdecl function below.
@_cdecl("FBiOSTargetOperationFromFuture")
func FBiOSTargetOperationFromFuture(_ completed: FBFuture<NSNull>) -> FBiOSTargetOperation {
  return FBiOSTargetOperationWrapper(completed: completed)
}
