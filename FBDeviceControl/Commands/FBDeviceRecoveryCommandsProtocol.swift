/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBDeviceRecoveryCommandsProtocol: NSObjectProtocol {

  @objc func enterRecovery() -> FBFuture<NSNull>

  @objc func exitRecovery() -> FBFuture<NSNull>
}

// FBDevice conforms at runtime via ObjC forwardingTargetForSelector:
// Do not add Swift extension conformance here.
