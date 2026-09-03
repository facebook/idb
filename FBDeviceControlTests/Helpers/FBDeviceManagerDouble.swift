/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBDeviceControl
import Foundation

/// A concrete `FBDeviceManager` for tests.
///
/// `constructPublic` returns a plain `NSObject` stand-in and `extractPrivateReference` always
/// returns nil, so every `deviceConnected` call takes the "appeared for the first time" path.
final class FBDeviceManagerDouble: FBDeviceManager<NSObject> {

  override func startListening() throws {}

  override func stopListening() throws {}

  override func constructPublic(_ privateDevice: CFTypeRef, identifier: String, info: [String: Any]?) -> NSObject {
    NSObject()
  }

  override class func updatePublicReference(
    _ publicDevice: NSObject,
    privateDevice: CFTypeRef,
    identifier: String,
    info: [String: Any]?
  ) {}

  override class func extractPrivateReference(_ publicDevice: NSObject) -> Unmanaged<AnyObject>? {
    nil
  }
}
