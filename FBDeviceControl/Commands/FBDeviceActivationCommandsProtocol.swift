/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBDeviceActivationCommandsProtocol: NSObjectProtocol {

  @objc func activate() -> FBFuture<NSNull>
}

// FBDevice conforms at runtime via ObjC forwardingTargetForSelector:
// Do not add Swift extension conformance here - it causes compile errors
// because FBDevice doesn't implement these methods directly.
