/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBPowerCommands: NSObjectProtocol, FBiOSTargetCommand {

  @objc func shutdown() -> FBFuture<NSNull>

  @objc func reboot() -> FBFuture<NSNull>
}
