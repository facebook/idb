/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Unlike `FBSubprocess`, no exit code or signal status is available.
public protocol FBLaunchedApplication: AnyObject {

  /// The Bundle Identifier of the Launched Application.
  var bundleID: String { get }

  /// The Process Identifier of the Launched Application.
  var processIdentifier: pid_t { get }

  /// Targets that cannot observe termination throw.
  func waitForTermination() async throws

  /// Terminates the launched application.
  func terminate() async throws
}
