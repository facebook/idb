/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBLifecycleCommands: NSObjectProtocol, FBiOSTargetCommand {

  @objc(resolveState:)
  func resolveState(_ state: FBiOSTargetState) -> FBFuture<NSNull>

  @objc(resolveLeavesState:)
  func resolveLeavesState(_ state: FBiOSTargetState) -> FBFuture<NSNull>
}
