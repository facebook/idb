/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBEraseCommands`.
public protocol AsyncEraseCommands: AnyObject {

  func erase() async throws
}

/// Default bridge implementation against the legacy `FBEraseCommands` protocol.
extension AsyncEraseCommands where Self: FBEraseCommands {

  public func erase() async throws {
    try await bridgeFBFutureVoid(self.erase())
  }
}
