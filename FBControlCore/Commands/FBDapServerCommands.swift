/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBDapServerCommand: NSObjectProtocol, FBiOSTargetCommand {

  @objc(launchDapServer:stdIn:stdOut:)
  func launchDapServer(_ dapPath: Any, stdIn: FBProcessInput<AnyObject>, stdOut: FBDataConsumer) -> FBFuture<FBSubprocess<AnyObject, FBDataConsumer, NSString>>
}
