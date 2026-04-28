/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBMemoryCommands`.
public protocol AsyncMemoryCommands: AnyObject {

  func simulateMemoryWarning() async throws
}

/// Default bridge implementation against the legacy `FBMemoryCommands`
/// protocol.
extension AsyncMemoryCommands where Self: FBMemoryCommands {

  public func simulateMemoryWarning() async throws {
    try await bridgeFBFutureVoid(self.simulateMemoryWarning())
  }
}
