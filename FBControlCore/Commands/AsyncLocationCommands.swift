/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBLocationCommands`.
public protocol AsyncLocationCommands: AnyObject {

  func overrideLocation(longitude: Double, latitude: Double) async throws
}

/// Default bridge implementation against the legacy `FBLocationCommands`
/// protocol.
extension AsyncLocationCommands where Self: FBLocationCommands {

  public func overrideLocation(longitude: Double, latitude: Double) async throws {
    try await bridgeFBFutureVoid(self.overrideLocation(withLongitude: longitude, latitude: latitude))
  }
}
