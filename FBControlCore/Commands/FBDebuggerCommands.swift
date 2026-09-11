/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public protocol DebugServer: AnyObject {

  var lldbBootstrapCommands: [String] { get }

  /// Cancels the debug server and waits for teardown to complete.
  func cancel() async throws
}
