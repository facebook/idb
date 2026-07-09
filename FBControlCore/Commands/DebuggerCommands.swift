/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public protocol DebuggerCommands: AnyObject {

  func launchDebugServer(
    forHostApplication application: FBBundleDescriptor,
    port: in_port_t
  ) async throws -> any FBDebugServer
}
