/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// An in-memory representation of a launched application.
/// This is distinct from FBSubprocess, as exit codes for the process are not available.
/// However, an event for when termination of the application occurs is communicated through a Future.
@objc public protocol FBLaunchedApplication: NSObjectProtocol {

  /// The Bundle Identifier of the Launched Application.
  @objc var bundleID: String { get }

  /// The Process Identifier of the Launched Application.
  @objc var processIdentifier: pid_t { get }

  /// A future that resolves when the Application has terminated.
  /// Cancelling this Future will cause the application to terminate.
  /// Exit code/Signal status of the launched process is not available.
  @objc var applicationTerminated: FBFuture<NSNull> { get }
}
