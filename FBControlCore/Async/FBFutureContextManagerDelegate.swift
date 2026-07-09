/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The Delegate for a Context Manager
@objc public protocol FBFutureContextManagerDelegate: NSObjectProtocol {

  /// Prepare the Resource.
  ///
  /// - Parameter logger: the logger to use.
  /// - Returns: a Future that resolves with the prepared context.
  @objc(prepare:)
  func prepare(_ logger: FBControlCoreLogger) -> FBFuture<AnyObject>

  /// Teardown the resource.
  ///
  /// - Parameters:
  ///   - context: the context to use.
  ///   - logger: the logger to use.
  /// - Returns: a Future wrapping NSNull.
  @discardableResult
  @objc(teardown:logger:)
  func teardown(_ context: Any, logger: FBControlCoreLogger) -> FBFuture<NSNull>

  /// The Name of the Resource.
  @objc var contextName: String { get }

  /// The amount of time to allow the resource to be held with no-one utilizing it.
  /// This is useful for ensuring that the same connection
  @objc var contextPoolTimeout: NSNumber? { get }

  /// Allows the context to be shared.
  @objc var isContextSharable: Bool { get }
}
