/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBSocketForwardingCommands: NSObjectProtocol {

  @objc(drainLocalFileInput:localFileOutput:remotePort:)
  func drainLocalFileInput(_ localFileDescriptorInput: Int32, localFileOutput localFileDescriptorOutput: Int32, remotePort: Int32) -> FBFuture<NSNull>
}

// FBDevice conforms at runtime via ObjC forwardingTargetForSelector:
// Do not add Swift extension conformance here.
