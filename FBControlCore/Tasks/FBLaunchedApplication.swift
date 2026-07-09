/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// An in-memory representation of a launched application.
/// This is distinct from FBSubprocess, as exit codes for the process are not available.
public protocol FBLaunchedApplication: AnyObject {

  /// The Bundle Identifier of the Launched Application.
  var bundleID: String { get }

  /// The Process Identifier of the Launched Application.
  var processIdentifier: pid_t { get }

  /// Awaits the natural termination of the launched application.
  /// Not every target can observe termination; those that cannot will throw.
  /// The process's exit code / signal status is not available.
  func waitForTermination() async throws

  /// Terminates the launched application.
  func terminate() async throws
}
