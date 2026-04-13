/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBDebugServer: FBiOSTargetOperation {

  @objc var lldbBootstrapCommands: [String] { get }
}

@objc public protocol FBDebuggerCommands: NSObjectProtocol, FBiOSTargetCommand {

  @objc(launchDebugServerForHostApplication:port:)
  func launchDebugServer(forHostApplication application: FBBundleDescriptor, port: in_port_t) -> FBFuture<FBDebugServer>
}
